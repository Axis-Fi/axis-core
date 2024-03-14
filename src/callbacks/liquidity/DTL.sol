// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

abstract contract DirectToLiquidity is BaseCallback {
    // ========== ERRORS ========== //

    // ========== STATE VARIABLES ========== //

    // TODO determine structure for storing pool configuration and vesting information

    // ========== CALLBACK FUNCTIONS ========== //

    function _onCreate(
        uint96 lotId_,
        address,
        address baseToken_,
        address quoteToken_,
        uint96 capacity_,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        // TODO
        // Decode pool configuration and vesting information from callback data
        // [ ] - Percent of proceeds to use in pool
        // [ ] - Duration to vest the LP tokens
        // [ ] - Pool specific info (e.g. fee tier, tick spacing, etc.)
        // Use baseToken and quoteToken as assets in new pool
        // Store capacity of market (should have that amount extra in this contract to pair)

        // Should we assume the callback is sending base tokens? Account for both cases?
        // Assume that the auction is prefunded since you should only create this with a claimProceeds callback
        // which is only implemented for Batch Auctions
    }

    function _onCancel(uint96, uint96, bool, bytes calldata) internal pure override {
        // TODO only needed if sending base tokens + prefunded
    }

    function _onCurate(uint96, uint96, bool, bytes calldata) internal pure override {
        // TODO only needed if sending base tokens + prefunded
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

        // Conditionally, create vesting tokens with the received LP tokens
        // Send spot or vesting LP tokens to seller
    }
}
