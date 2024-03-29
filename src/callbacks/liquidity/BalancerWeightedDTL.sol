// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IWeightedPoolFactory} from "src/lib/balancer/IWeightedPoolFactory.sol";
import {IVault} from "src/lib/balancer/IVault.sol";
import {IWeightedPool} from "src/lib/balancer/IWeightedPool.sol";
import {IAsset} from "src/lib/balancer/IAsset.sol";
import {IRateProvider} from "src/lib/balancer/IRateProvider.sol";

// Callbacks
import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";

contract UniswapV2DirectToLiquidity is BaseDirectToLiquidity {
    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onCreate callback
    /// @dev        This will be encoded in the `callbackData_.implParams` parameter
    ///
    /// @param      name        The name of the pool
    /// @param      symbol      The symbol of the pool
    /// @param      swapFee     The swap fee of the pool (between `_MIN_SWAP_FEE_PERCENTAGE` and `_MAX_SWAP_FEE_PERCENTAGE`)
    struct BalancerOnCreateParams {
        string name;
        string symbol;
        uint256 swapFeePercentage;
    }

    /// @notice     Parameters for the onClaimProceeds callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      salt                    The salt used to create the pool
    struct BalancerOnClaimProceedsParams {
        bytes32 salt;
    }

    // ========== STATE VARIABLES ========== //

    // Source: https://github.com/balancer/balancer-v2-monorepo/blob/ac63d64018c6331248c7d77b9f317a06cced0243/pkg/pool-weighted/contracts/managed/ManagedPoolSettings.sol#L98
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 95e16; // 95%
    uint256 private constant _MAX_WEIGHT = 1e18;

    /// @notice     The Balancer weighted pool factory
    /// @dev        This contract is used to create weighted pools
    IWeightedPoolFactory public poolFactory;

    /// @notice     The Balancer vault
    /// @dev        This contract is used to deposit tokens into the pool
    IVault public vault;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address seller_,
        address poolFactory_,
        address vault_
    ) BaseDirectToLiquidity(auctionHouse_, seller_) {
        if (poolFactory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        poolFactory = IWeightedPoolFactory(poolFactory_);

        if (vault_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        vault = IVault(vault_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Validates the parameters
    function __onCreate(
        uint96,
        address,
        address,
        address,
        uint96,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        OnCreateParams memory params = abi.decode(callbackData_, (OnCreateParams));
        BalancerOnCreateParams memory implParams =
            abi.decode(params.implParams, (BalancerOnCreateParams));

        // Validate implementation parameters
        // Name
        if (bytes(implParams.name).length == 0) {
            revert Callback_InvalidParams();
        }

        // Symbol
        if (bytes(implParams.symbol).length == 0) {
            revert Callback_InvalidParams();
        }

        // Swap fee
        if (
            implParams.swapFeePercentage < _MIN_SWAP_FEE_PERCENTAGE
                || implParams.swapFeePercentage > _MAX_SWAP_FEE_PERCENTAGE
        ) {
            revert Callback_InvalidParams();
        }

        // Balancer supports multiple pools per token combination, so there is no need to check if the pool exists here.
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Creates the pool if necessary
    ///             - Deposits the tokens into the pool
    function _mintAndDeposit(
        uint96 lotId_,
        uint256 quoteTokenAmount_,
        uint256 baseTokenAmount_,
        bytes memory callbackData_
    ) internal virtual override returns (ERC20 poolToken) {
        // Decode the callback data
        BalancerOnClaimProceedsParams memory params =
            abi.decode(callbackData_, (BalancerOnClaimProceedsParams));

        DTLConfiguration memory config = lotConfiguration[lotId_];
        BalancerOnCreateParams memory implParams =
            abi.decode(config.implParams, (BalancerOnCreateParams));

        address poolAddress;
        {
            ERC20 quoteToken = ERC20(config.quoteToken);
            ERC20 baseToken = ERC20(config.baseToken);

            // Order the tokens
            bool quoteTokenIsToken0 = config.quoteToken < config.baseToken;
            ERC20[] memory poolTokens = new ERC20[](2);
            poolTokens[0] = quoteTokenIsToken0 ? quoteToken : baseToken;
            poolTokens[1] = quoteTokenIsToken0 ? baseToken : quoteToken;

            // Weights
            uint256[] memory weights = new uint256[](2);
            {
                // Shift into the same decimals
                uint256 quoteTokenAmount = quoteTokenAmount_ * 1e18 / 10 ** quoteToken.decimals();
                uint256 baseTokenAmount = baseTokenAmount_ * 1e18 / 10 ** baseToken.decimals();

                // Get relative percentage
                uint256 totalAmount = quoteTokenAmount + baseTokenAmount;
                uint256 weightedQuoteTokenAmount =
                    FixedPointMathLib.mulDivUp(quoteTokenAmount, _MAX_WEIGHT, totalAmount);
                uint256 weightedBaseTokenAmount =
                    FixedPointMathLib.mulDivDown(baseTokenAmount, _MAX_WEIGHT, totalAmount);

                weights[0] = quoteTokenIsToken0 ? weightedQuoteTokenAmount : weightedBaseTokenAmount;
                weights[1] = quoteTokenIsToken0 ? weightedBaseTokenAmount : weightedQuoteTokenAmount;
            }

            // Rate providers
            IRateProvider[] memory rateProviders = new IRateProvider[](2);
            rateProviders[0] = IRateProvider(address(0));
            rateProviders[1] = IRateProvider(address(0));

            // Create and initialize the pool
            poolAddress = poolFactory.create(
                implParams.name,
                implParams.symbol,
                poolTokens,
                weights,
                rateProviders,
                implParams.swapFeePercentage,
                seller,
                params.salt
            );
        }

        // Approve the vault to spend the tokens
        ERC20(config.quoteToken).approve(address(vault), quoteTokenAmount_);
        ERC20(config.baseToken).approve(address(vault), baseTokenAmount_);

        // Deposit into the pool
        {
            // Get the pool id
            IWeightedPool pool = IWeightedPool(poolAddress);
            bytes32 poolId = pool.getPoolId();

            bool quoteTokenIsToken0 = config.quoteToken < config.baseToken;

            IAsset[] memory assets = new IAsset[](2);
            assets[0] = quoteTokenIsToken0 ? IAsset(config.quoteToken) : IAsset(config.baseToken);
            assets[1] = quoteTokenIsToken0 ? IAsset(config.baseToken) : IAsset(config.quoteToken);

            uint256[] memory maxAmountsIn = new uint256[](2);
            maxAmountsIn[0] = quoteTokenIsToken0 ? quoteTokenAmount_ : baseTokenAmount_;
            maxAmountsIn[1] = quoteTokenIsToken0 ? baseTokenAmount_ : quoteTokenAmount_;

            IVault.JoinPoolRequest memory joinRequest = IVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: abi.encode(""),
                fromInternalBalance: false
            });

            // Deposit
            vault.joinPool(poolId, address(this), address(this), joinRequest);
        }

        // Remove any dangling approvals
        // This is necessary, since the router may not spend all available tokens
        ERC20(config.quoteToken).approve(address(vault), 0);
        ERC20(config.baseToken).approve(address(vault), 0);

        return ERC20(poolAddress);
    }
}
