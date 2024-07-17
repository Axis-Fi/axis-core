// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProof} from "@openzeppelin-contracts-4.9.2/utils/cryptography/MerkleProof.sol";

import {MerkleAllowlist} from "src/callbacks/allowlists/MerkleAllowlist.sol";
import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @title  AllocatedMerkleAllowlist
/// @notice This contract extends the MerkleAllowlist contract to implement a merkle tree-based allowlist for buyers to participate in an auction.
///         In this implementation, each buyer has an individual purchase limit that is set.
contract AllocatedMerkleAllowlist is MerkleAllowlist {
    // ========== ERRORS ========== //

    /// @notice Error message when the bid amount exceeds the limit assigned to a buyer
    error Callback_ExceedsLimit();

    // ========== STATE VARIABLES ========== //

    /// @notice Tracks the cumulative amount spent by a buyer on a lot
    mapping(uint96 lotId => mapping(address buyer => uint256 spent)) public lotBuyerSpent;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: false
    // onCurate: false
    // onPurchase: true
    // onBid: true
    // onSettle: false
    // receiveQuoteTokens: false
    // sendBaseTokens: false
    // Contract prefix should be: 10011000 = 0x98

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_
    ) MerkleAllowlist(auctionHouse_, permissions_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseCallback
    /// @dev        This function performs the following:
    ///             - Calls the `_onBuy()` function to validate the buyer's purchase
    ///
    /// @param      callbackData_   abi-encoded data: (bytes32[], uint256) representing the merkle proof and allocated amount
    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal override {
        _onBuy(lotId_, buyer_, amount_, callbackData_);
    }

    /// @inheritdoc BaseCallback
    /// @dev        This function performs the following:
    ///             - Calls the `_onBuy()` function to validate the buyer's bid
    ///
    /// @param      callbackData_   abi-encoded data: (bytes32[], uint256) representing the proof and allocated amount
    function _onBid(
        uint96 lotId_,
        uint64,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal override {
        _onBuy(lotId_, buyer_, amount_, callbackData_);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _onBuy(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal {
        // Validate that the buyer is allowed to participate

        // Decode the merkle proof and allocated amount from buyer submitted callback data
        (bytes32[] memory proof, uint256 allocatedAmount) =
            abi.decode(callbackData_, (bytes32[], uint256));

        // Get the leaf for the buyer
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(buyer_, allocatedAmount))));

        // Validate the merkle proof
        if (!MerkleProof.verify(proof, lotMerkleRoot[lotId_], leaf)) {
            revert Callback_NotAuthorized();
        }

        // Validate that the buyer can spend the amount
        // They cannot spend over the allocated amount
        if (lotBuyerSpent[lotId_][buyer_] + amount_ > allocatedAmount) {
            revert Callback_ExceedsLimit();
        }

        // Update the buyer's spent amount
        lotBuyerSpent[lotId_][buyer_] += amount_;
    }
}
