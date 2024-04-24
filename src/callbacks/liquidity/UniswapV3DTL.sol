// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";

// Uniswap
import {IUniswapV3Pool} from "uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {TickMath} from "uniswap-v3-core/libraries/TickMath.sol";

// G-UNI
import {IGUniFactory} from "g-uni-v1-core/interfaces/IGUniFactory.sol";
import {GUniPool} from "g-uni-v1-core/GUniPool.sol";

// Callbacks
import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";

/// @title      UniswapV3DirectToLiquidity
/// @notice     This Callback contract deposits the proceeds from a batch auction into a Uniswap V3 pool
///             in order to create liquidity immediately.
///
///             The LP tokens can optionally vest to the auction seller.
///
///             An important risk to consider: if the auction's base token is available and liquid, a third-party
///             could front-run the auction by creating the pool before the auction ends. This would allow them to
///             manipulate the price of the pool and potentially profit from the eventual deposit of the auction proceeds.
///
/// @dev        As a general rule, this callback contract does not retain balances of tokens between calls.
///             Transfers are performed within the same function that requires the balance.
contract UniswapV3DirectToLiquidity is BaseDirectToLiquidity {
    // ========== ERRORS ========== //

    error Callback_Params_PoolFeeNotEnabled();

    error Callback_Slippage(address token_, uint256 amountActual_, uint256 amountMin_);

    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onClaimProceeds callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      maxSlippage             The maximum slippage allowed when adding liquidity (in terms of `MAX_PERCENT`)
    struct OnClaimProceedsParams {
        uint24 maxSlippage;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Uniswap V3 Factory contract
    /// @dev        This contract is used to create Uniswap V3 pools
    IUniswapV3Factory public uniV3Factory;

    /// @notice     The G-UNI Factory contract
    /// @dev        This contract is used to create the ERC20 LP tokens
    IGUniFactory public gUniFactory;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address uniV3Factory_,
        address gUniFactory_
    ) BaseDirectToLiquidity(auctionHouse_) {
        if (uniV3Factory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        uniV3Factory = IUniswapV3Factory(uniV3Factory_);

        if (gUniFactory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        gUniFactory = IGUniFactory(gUniFactory_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function performs the following:
    ///             - Validates the input data
    ///
    ///             This function reverts if:
    ///             - OnCreateParams.implParams.poolFee is not enabled
    ///             - The pool for the token and fee combination already exists
    function __onCreate(
        uint96,
        address,
        address baseToken_,
        address quoteToken_,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        OnCreateParams memory params = abi.decode(callbackData_, (OnCreateParams));
        (uint24 poolFee) = abi.decode(params.implParams, (uint24));

        // Validate the parameters
        // Pool fee
        // Fee not enabled
        if (uniV3Factory.feeAmountTickSpacing(poolFee) == 0) {
            revert Callback_Params_PoolFeeNotEnabled();
        }

        // Check that the pool does not exist
        if (uniV3Factory.getPool(baseToken_, quoteToken_, poolFee) != address(0)) {
            revert Callback_Params_PoolExists();
        }
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function performs the following:
    ///             - Creates and initializes the pool, if necessary
    ///             - Deploys a pool token to wrap the Uniswap V3 position as an ERC-20 using GUni
    ///             - Uses the `GUniPool.getMintAmounts()` function to calculate the quantity of quote and base tokens required, given the current pool liquidity
    ///             - Mint the LP tokens
    ///
    ///             The assumptions are:
    ///             - the callback has `quoteTokenAmount_` quantity of quote tokens (as `receiveQuoteTokens` flag is set)
    ///             - the callback has `baseTokenAmount_` quantity of base tokens
    function _mintAndDeposit(
        uint96 lotId_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_,
        bytes memory callbackData_
    ) internal virtual override returns (ERC20 poolToken) {
        // Decode the callback data
        OnClaimProceedsParams memory params = abi.decode(callbackData_, (OnClaimProceedsParams));

        // Extract the pool fee from the implParams
        (uint24 poolFee) = abi.decode(lotConfiguration[lotId_].implParams, (uint24));

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = quoteToken_ < baseToken_;

        // Create and initialize the pool if necessary
        {
            // Determine sqrtPriceX96
            uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
                quoteToken_, baseToken_, quoteTokenAmount_, baseTokenAmount_
            );

            // If the pool already exists and is initialized, it will have no effect
            // Please see the risks section in the contract documentation for more information
            _createAndInitializePoolIfNecessary(
                quoteTokenIsToken0 ? quoteToken_ : baseToken_,
                quoteTokenIsToken0 ? baseToken_ : quoteToken_,
                poolFee,
                sqrtPriceX96
            );
        }

        // Deploy the pool token
        address poolTokenAddress;
        {
            // Adjust the full-range ticks according to the tick spacing for the current fee
            int24 tickSpacing = uniV3Factory.feeAmountTickSpacing(poolFee);

            // Create an unmanaged pool
            // The range of the position will not be changed after deployment
            // Fees will also be collected at the time of withdrawal
            poolTokenAddress = gUniFactory.createPool(
                quoteTokenIsToken0 ? quoteToken_ : baseToken_,
                quoteTokenIsToken0 ? baseToken_ : quoteToken_,
                poolFee,
                TickMath.MIN_TICK / tickSpacing * tickSpacing,
                TickMath.MAX_TICK / tickSpacing * tickSpacing
            );
        }

        // Deposit into the pool
        {
            GUniPool gUniPoolToken = GUniPool(poolTokenAddress);

            // Calculate the quantity of quote and base tokens required to deposit into the pool at the current tick
            (uint256 amount0Actual, uint256 amount1Actual, uint256 poolTokenQuantity) =
            gUniPoolToken.getMintAmounts(
                quoteTokenIsToken0 ? quoteTokenAmount_ : baseTokenAmount_,
                quoteTokenIsToken0 ? baseTokenAmount_ : quoteTokenAmount_
            );

            // Revert if the slippage is too high
            {
                uint256 quoteTokenRequired = quoteTokenIsToken0 ? amount0Actual : amount1Actual;

                // Ensures that `quoteTokenRequired` (as specified by GUniPool) is within the slippage range from the actual quote token amount
                uint256 lower = _getAmountWithSlippage(quoteTokenAmount_, params.maxSlippage);
                if (quoteTokenRequired < lower) {
                    revert Callback_Slippage(quoteToken_, quoteTokenRequired, lower);
                }

                // Approve the vault to spend the tokens
                ERC20(quoteToken_).approve(address(poolTokenAddress), quoteTokenRequired);
            }
            {
                uint256 baseTokenRequired = quoteTokenIsToken0 ? amount1Actual : amount0Actual;

                // Ensures that `baseTokenRequired` (as specified by GUniPool) is within the slippage range from the actual base token amount
                uint256 lower = _getAmountWithSlippage(baseTokenAmount_, params.maxSlippage);
                if (baseTokenRequired < lower) {
                    revert Callback_Slippage(baseToken_, baseTokenRequired, lower);
                }

                // Approve the vault to spend the tokens
                ERC20(baseToken_).approve(address(poolTokenAddress), baseTokenRequired);
            }

            // Mint the LP tokens
            // The parent callback is responsible for transferring any leftover quote and base tokens
            gUniPoolToken.mint(poolTokenQuantity, address(this));
        }

        poolToken = ERC20(poolTokenAddress);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @dev    Copied from UniswapV3's PoolInitializer (which is GPL >= 2)
    function _createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) internal returns (address pool) {
        require(token0 < token1);
        pool = uniV3Factory.getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = uniV3Factory.createPool(token0, token1, fee);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing,,,,,,) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}
