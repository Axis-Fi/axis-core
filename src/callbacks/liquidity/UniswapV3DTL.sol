// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

import {TickMath} from "uniswap-v3-core/libraries/TickMath.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title      UniswapV3DirectToLiquidity
/// @notice     This Callback contract deposits the proceeds from a batch auction into a Uniswap V3 pool
///             in order to create liquidity immediately.
///
///             The LP tokens can optionally vest to the auction seller.
contract UniswapV3DirectToLiquidity is BaseCallback {
    // ========== ERRORS ========== //

    error Callback_InsufficientBalance(
        address token_, uint256 amountRequired_, uint256 amountActual_
    );

    // ========== STRUCTS ========== //

    /// @notice     Configuration for the DTL callback
    struct DTLConfiguration {
        address baseToken;
        address quoteToken;
        uint96 lotCapacity;
        uint96 lotCuratorPayout;
        uint24 proceedsUtilisationPercent;
        uint24 poolFee;
        uint48 vestingStart;
        uint48 vestingExpiry;
    }

    /// @notice     Parameters used in the onCreate callback
    ///
    /// @param      proceedsUtilisationPercent   The percentage of the proceeds to use in the pool
    /// @param      poolFee                      The Uniswap V3 fee tier for the pool
    /// @param      vestingStart                 The start of the vesting period for the LP tokens (0 if disabled)
    /// @param      vestingExpiry                The end of the vesting period for the LP tokens (0 if disabled)
    struct DTLParams {
        uint24 proceedsUtilisationPercent;
        uint24 poolFee;
        uint48 vestingStart;
        uint48 vestingExpiry;
    }

    // ========== STATE VARIABLES ========== //

    uint24 public constant MAX_PERCENT = 1e5;
    uint24 public constant MAX_POOL_FEE = 1e6;

    /// @notice     Maps the lot id to the DTL configuration
    mapping(uint96 lotId => DTLConfiguration) public lotConfiguration;

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address seller_
    ) BaseCallback(auctionHouse_, permissions_, seller_) {
        // Ensure that the required permissions are met
        if (
            !permissions_.onCreate || !permissions_.onCancel || !permissions_.onCurate
                || !permissions_.onClaimProceeds || !permissions_.receiveQuoteTokens
        ) {
            revert Callback_InvalidParams();
        }
    }

    // [ ] Consider using bunni to manage the pool tokens
    // [ ] Functions to handle vesting LP tokens. Can we reuse LinearVesting?
    // [ ] Enable the seller to withdraw base tokens, quote tokens

    // ========== CALLBACK FUNCTIONS ========== //

    /// @notice     Callback for when a lot is created
    /// @dev        This function reverts if:
    ///             - DTLParams.proceedsUtilisationPercent is out of bounds
    ///             - DTLParams.poolFee is out of bounds
    ///             - DTLParams.vestingStart or DTLParams.vestingExpiry do not pass validation
    ///
    /// @param      lotId_          The lot ID
    /// @param      baseToken_      The base token address
    /// @param      quoteToken_     The quote token address
    /// @param      capacity_       The capacity of the lot
    /// @param      prefund_        Whether the callback has to prefund the lot
    /// @param      callbackData_   Encoded DTLParams struct
    function _onCreate(
        uint96 lotId_,
        address,
        address baseToken_,
        address quoteToken_,
        uint96 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Decode callback data into the params
        // TODO check length of callbackData to provide a more helpful error message
        DTLParams memory params = abi.decode(callbackData_, (DTLParams));

        // Validate the parameters
        // Proceeds utilisation
        if (
            params.proceedsUtilisationPercent == 0
                || params.proceedsUtilisationPercent > MAX_PERCENT
        ) {
            revert Callback_InvalidParams();
        }

        // Pool fee
        // TODO can the poolFee be 0?
        if (params.poolFee > MAX_POOL_FEE) {
            revert Callback_InvalidParams();
        }

        // TODO vesting start < expiry (use LinearVesting.validate()?)

        // TODO assert that the pool does not exist

        // Store the configuration
        lotConfiguration[lotId_] = DTLConfiguration({
            baseToken: baseToken_,
            quoteToken: quoteToken_,
            lotCapacity: capacity_,
            lotCuratorPayout: 0,
            proceedsUtilisationPercent: params.proceedsUtilisationPercent,
            poolFee: params.poolFee,
            vestingStart: params.vestingStart,
            vestingExpiry: params.vestingExpiry
        });

        // If prefund_ is true, then the callback needs to transfer the capacity in base tokens to the auction house
        if (prefund_) {
            // No need to verify the sender, as it is done in BaseCallback
            ERC20(baseToken_).transfer(msg.sender, capacity_);
        }
    }

    function _onCancel(uint96, uint96, bool, bytes calldata) internal pure override {
        // TODO mark as cancelled/claimed?
    }

    function _onCurate(
        uint96 lotId_,
        uint96 curatorPayout_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal override {
        // If prefunded, then the callback needs to transfer the curatorPayout_ in base tokens to the auction house
        if (prefund_) {
            DTLConfiguration storage config = lotConfiguration[lotId_];

            // Update the funding
            config.lotCuratorPayout = curatorPayout_;

            // No need to verify the sender, as it is done in BaseCallback
            ERC20(config.baseToken).transfer(msg.sender, curatorPayout_);
        }
    }

    function _onPurchase(
        uint96,
        address,
        uint96,
        uint96,
        bool,
        bytes calldata
    ) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onBid(uint96, uint64, address, uint96, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onClaimProceeds(
        uint96 lotId_,
        uint96 proceeds_,
        uint96 refund_,
        bytes calldata callbackData_
    ) internal virtual override {
        DTLConfiguration memory config = lotConfiguration[lotId_];

        // Calculate the actual lot capacity that was used
        uint96 capacityUtilised;
        {
            // If curation is enabled, refund_ will also contain the refund on the curator payout. Adjust for that.
            // Example:
            // 100 capacity + 10 curator
            // 90 capacity sold, 9 curator payout
            // 11 refund
            // Utilisation = 1 - 11/110 = 90%
            uint96 utilisationPercent =
                1e5 - refund_ / (config.lotCapacity + config.lotCuratorPayout);

            capacityUtilised = (config.lotCapacity * utilisationPercent) / MAX_PERCENT;
        }

        // Calculate the base tokens required to create the pool
        uint96 baseTokensRequired =
            _baseTokensRequiredForPool(capacityUtilised, config.proceedsUtilisationPercent);

        // Check that there is still enough capacity to create the pool
        {
            uint256 baseTokenBalance = ERC20(config.baseToken).balanceOf(address(this));
            if (baseTokenBalance < baseTokensRequired) {
                revert Callback_InsufficientBalance(
                    config.baseToken, baseTokensRequired, baseTokenBalance
                );
            }
        }

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = config.quoteToken < config.baseToken;

        // Determine the initial price
        uint96 initialTick;
        {
            // // Determine the price of token0 in terms of token1
            // uint256 price;
            // if (quoteTokenIsToken0) {
            //     price = proceeds_ * 10 ** ERC20(config.baseToken).decimals() / capacityUtilised;
            // }
            // else {
            //     price = capacityUtilised * 10 ** ERC20(config.quoteToken).decimals() / proceeds_;
            // }

            // Determine sqrtPriceX96
            uint160 sqrtPriceX96;
            {
                uint160 amount0 = quoteTokenIsToken0 ? proceeds_ : capacityUtilised;
                uint160 amount1 = quoteTokenIsToken0 ? capacityUtilised : proceeds_;

                uint160 numerator = amount1 << 192;
                uint160 denominator = amount0;
                uint160 ratioX192 = (numerator / denominator);
                // sqrtPriceX96 =
            }

            // TODO Determine the tick
        }

        // Create the pool

        // Deposit into the pool

        // Conditionally, create vesting tokens with the received LP tokens
        // Send spot or vesting LP tokens to seller
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _baseTokensRequiredForPool(
        uint96 capacity_,
        uint24 proceedsUtilisationPercent_
    ) internal pure returns (uint96) {
        return (capacity_ * proceedsUtilisationPercent_) / MAX_PERCENT;
    }
}
