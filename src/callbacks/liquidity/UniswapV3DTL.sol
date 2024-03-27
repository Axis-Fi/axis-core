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
import {BaseUniswapDirectToLiquidity} from "src/callbacks/liquidity/BaseUniswapDTL.sol";

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
contract UniswapV3DirectToLiquidity is BaseUniswapDirectToLiquidity {
    // ========== ERRORS ========== //

    error Callback_Params_PoolFeeNotEnabled();

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
        address seller_,
        address uniV3Factory_,
        address gUniFactory_
    ) BaseUniswapDirectToLiquidity(auctionHouse_, seller_) {
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

    /// @inheritdoc BaseUniswapDirectToLiquidity
    /// @dev        This function performs the following:
    ///             - Validates the input data
    ///
    ///             This function reverts if:
    ///             - DTLParams.poolFee is not enabled
    ///             - The pool for the token and fee combination already exists
    function __onCreate(
        uint96 lotId_,
        address,
        address baseToken_,
        address quoteToken_,
        uint96,
        bool,
        bytes calldata callbackData_
    ) internal virtual override onlyIfLotDoesNotExist(lotId_) {
        DTLParams memory params = abi.decode(callbackData_, (DTLParams));

        // Validate the parameters
        // Pool fee
        // Fee not enabled
        if (uniV3Factory.feeAmountTickSpacing(params.poolFee) == 0) {
            revert Callback_Params_PoolFeeNotEnabled();
        }

        // Check that the pool does not exist
        if (uniV3Factory.getPool(baseToken_, quoteToken_, params.poolFee) != address(0)) {
            revert Callback_Params_PoolExists();
        }
    }

    /// @inheritdoc BaseUniswapDirectToLiquidity
    /// @dev        This function performs the following:
    ///             - Creates and initializes the pool, if necessary
    ///             - Deploys a pool token to wrap the Uniswap V3 position as an ERC-20
    ///             - Deposits the tokens into the pool and mint the LP tokens
    ///
    ///             The assumptions are:
    ///             - the callback has `quoteTokenAmount_` quantity of quote tokens (as `receiveQuoteTokens` flag is set)
    ///             - the callback has `baseTokenAmount_` quantity of base tokens
    function _mintAndDeposit(
        uint96 lotId_,
        uint256 quoteTokenAmount_,
        uint256 baseTokenAmount_
    ) internal virtual override returns (ERC20 poolToken) {
        DTLConfiguration memory config = lotConfiguration[lotId_];

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = config.quoteToken < config.baseToken;

        // Create and initialize the pool if necessary
        {
            // Determine sqrtPriceX96
            uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
                config.quoteToken, config.baseToken, quoteTokenAmount_, baseTokenAmount_
            );

            // If the pool already exists and is initialized, it will have no effect
            // Please see the risks section in the contract documentation for more information
            _createAndInitializePoolIfNecessary(
                quoteTokenIsToken0 ? config.quoteToken : config.baseToken,
                quoteTokenIsToken0 ? config.baseToken : config.quoteToken,
                config.poolFee,
                sqrtPriceX96
            );
        }

        // Deploy the pool token
        address poolTokenAddress;
        {
            // Adjust the full-range ticks according to the tick spacing for the current fee
            int24 tickSpacing = uniV3Factory.feeAmountTickSpacing(config.poolFee);
            int24 minTick = TickMath.MIN_TICK / tickSpacing * tickSpacing;
            int24 maxTick = TickMath.MAX_TICK / tickSpacing * tickSpacing;

            // Create an unmanaged pool
            // The range of the position will not be changed after deployment
            // Fees will also be collected at the time of withdrawal
            poolTokenAddress = gUniFactory.createPool(
                quoteTokenIsToken0 ? config.quoteToken : config.baseToken,
                quoteTokenIsToken0 ? config.baseToken : config.quoteToken,
                config.poolFee,
                minTick,
                maxTick
            );
        }

        // Deposit into the pool
        uint256 poolTokenQuantity;
        {
            GUniPool gUniPoolToken = GUniPool(poolTokenAddress);

            // Approve the vault to spend the tokens
            ERC20(config.quoteToken).approve(address(poolTokenAddress), quoteTokenAmount_);
            ERC20(config.baseToken).approve(address(poolTokenAddress), baseTokenAmount_);

            // Calculate the mint amount
            (,, poolTokenQuantity) = gUniPoolToken.getMintAmounts(
                quoteTokenIsToken0 ? quoteTokenAmount_ : baseTokenAmount_,
                quoteTokenIsToken0 ? baseTokenAmount_ : quoteTokenAmount_
            );
        }

        // Mint LP tokens
        {
            GUniPool gUniPoolToken = GUniPool(poolTokenAddress);

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
