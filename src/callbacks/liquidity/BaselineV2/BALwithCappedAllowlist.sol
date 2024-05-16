// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BALwithAllowlist} from "src/callbacks/liquidity/BaselineV2/BALwithAllowlist.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @notice Capped allowlist version of the Baseline Axis Launch callback
/// @dev This contract only supports atomic auctions (i.e. Fixed Price Sale), unlike the regular allowlist version
contract BALwithCappedAllowlist is BALwithAllowlist {
    // ========== ERRORS ========== //
    error Callback_ExceedsLimit();

    // ========== STATE VARIABLES ========== //

    uint256 public buyerLimit;
    mapping(address => uint256) public buyerSpent;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: true
    // onBid: false
    // onSettle: false
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11110011 = 0xF3

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address baselineKernel_,
        address reserve_
    ) BALwithAllowlist(auctionHouse_, permissions_, baselineKernel_, reserve_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    function __onCreate(
        uint96,
        address,
        address,
        address,
        uint256,
        bool,
        bytes memory allowlistData_
    ) internal override {
        // Decode the merkle root from the callback data
        (bytes32 merkleRoot_, uint256 buyerLimit_) = abi.decode(allowlistData_, (bytes32, uint256));

        // Revert if buyer limit is 0, should just use regular allowlist version
        if (buyerLimit_ == 0) revert Callback_InvalidParams();

        // Set the merkle root and buyer limit
        merkleRoot = merkleRoot_;
        buyerLimit = buyerLimit_;
    }

    function ___onPurchase(
        uint96,
        address buyer_,
        uint256 amount_,
        uint256,
        bool,
        bytes calldata
    ) internal override {
        _canBuy(buyer_, amount_);
    }

    function _onBid(uint96, uint64, address, uint256, bytes calldata) internal pure override {
        revert Callback_NotImplemented();
    }

    function _onSettle(uint96, uint256, uint256, bytes calldata) internal pure override {
        revert Callback_NotImplemented();
    }

    // ========== INTERNAL FUNCTIONS ========== //
    function _canBuy(address buyer_, uint256 amount_) internal {
        // Check if the buyer has already spent their limit
        if (buyerSpent[buyer_] + amount_ > buyerLimit) {
            revert Callback_ExceedsLimit();
        }

        // Update the buyer spent amount
        buyerSpent[buyer_] += amount_;
    }
}
