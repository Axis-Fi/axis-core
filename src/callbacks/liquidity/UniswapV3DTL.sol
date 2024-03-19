// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

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
        uint24 proceedsUtilisationPercent;
        uint24 poolFee;
        int24 poolTickLower;
        int24 poolTickUpper;
        uint48 vestingStart;
        uint48 vestingExpiry;
    }

    /// @notice     Parameters used in the onCreate callback
    ///
    /// @param      proceedsUtilisationPercent   The percentage of the proceeds to use in the pool
    /// @param      poolFee                      The Uniswap V3 fee tier for the pool
    /// @param      poolTickLower                The lower tick of the Uniswap V3 pool
    /// @param      poolTickUpper                The upper tick of the Uniswap V3 pool
    /// @param      vestingStart                 The start of the vesting period for the LP tokens (0 if disabled)
    /// @param      vestingExpiry                The end of the vesting period for the LP tokens (0 if disabled)
    struct DTLParams {
        uint24 proceedsUtilisationPercent;
        uint24 poolFee;
        int24 poolTickLower;
        int24 poolTickUpper;
        uint48 vestingStart;
        uint48 vestingExpiry;
    }

    // ========== STATE VARIABLES ========== //

    uint24 public constant MAX_PERCENT = 1e5;

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
    // [ ] Enable the seller to withdraw base tokens

    // ========== CALLBACK FUNCTIONS ========== //

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
        // utilisation within range (> 0, < MAX_PERCENT)
        // pool fee
        // ticks: lower < upper, within range
        // vesting start < expiry (use LinearVesting.validate()?)
        // if sending base tokens, should have the capacity of base token to create the pool

        // Store the configuration
        lotConfiguration[lotId_] = DTLConfiguration({
            baseToken: baseToken_,
            quoteToken: quoteToken_,
            lotCapacity: capacity_,
            proceedsUtilisationPercent: params.proceedsUtilisationPercent,
            poolFee: params.poolFee,
            poolTickLower: params.poolTickLower,
            poolTickUpper: params.poolTickUpper,
            vestingStart: params.vestingStart,
            vestingExpiry: params.vestingExpiry
        });

        // If prefund_ is true, then the callback needs to transfer the capacity in base tokens to the auction house
        if (prefund_) {
            // No need to verify the sender, as it is done in BaseCallback
            ERC20(baseToken_).transfer(msg.sender, capacity_);
        }

        // Check that there is enough capacity to create the pool
        {
            uint96 baseTokensRequired =
                _baseTokensRequiredForPool(capacity_, params.proceedsUtilisationPercent);
            uint256 baseTokenBalance = ERC20(baseToken_).balanceOf(address(this));
            if (baseTokenBalance < baseTokensRequired) {
                revert Callback_InsufficientBalance(
                    baseToken_, baseTokensRequired, baseTokenBalance
                );
            }
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
        DTLConfiguration memory config = lotConfiguration[lotId_];

        // If prefunded, then the callback needs to transfer the curatorPayout_ in base tokens to the auction house
        if (prefund_) {
            // No need to verify the sender, as it is done in BaseCallback
            ERC20(config.baseToken).transfer(msg.sender, curatorPayout_);
        }

        // Check that there is still enough capacity to create the pool
        {
            uint96 baseTokensRequired =
                _baseTokensRequiredForPool(config.lotCapacity, config.proceedsUtilisationPercent);
            uint256 baseTokenBalance = ERC20(config.baseToken).balanceOf(address(this));
            if (baseTokenBalance < baseTokensRequired) {
                revert Callback_InsufficientBalance(
                    config.baseToken, baseTokensRequired, baseTokenBalance
                );
            }
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
        // TODO
        // Reduce expected tokens to deposit by the refund
        // Create pool and add proceeds and paired tokens to the pool

        // TODO how to determine the ratio between base and quote tokens?

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
