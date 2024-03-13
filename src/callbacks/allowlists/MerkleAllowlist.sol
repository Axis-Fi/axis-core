// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProofLib} from "lib/solady/src/utils/MerkleProofLib.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

contract MerkleAllowlist is BaseCallback {
    // ========== STATE VARIABLES ========== //

    mapping(uint96 => bytes32) public lotMerkleRoot;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: false
    // onCurate: false
    // onPurchase: true
    // onBid: true
    // onClaimProceeds: false
    // receiveQuoteTokens: false
    // sendBaseTokens: false
    // Contract prefix should be: 10011000 = 0x98

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address seller_
    ) BaseCallback(auctionHouse_, permissions_, seller_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    function _onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint96,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        // Decode the merkle root from the callback data
        bytes32 merkleRoot = abi.decode(callbackData_, (bytes32));

        // Set the merkle root
        lotMerkleRoot[lotId_] = merkleRoot;
    }

    function _onCancel(uint96, uint96, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onCurate(uint96, uint96, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint96 amount_,
        uint96 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Validate that the buyer is allowed to participate
        _canParticipate(lotId_, buyer_, callbackData_);

        // Call any additional implementation-specific logic
        __onPurchase(lotId_, buyer_, amount_, payout_, prefunded_, callbackData_);
    }

    function __onPurchase(
        uint96 lotId_,
        address buyer_,
        uint96 amount_,
        uint96 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual {}

    function _onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint96 amount_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Validate that the buyer is allowed to participate
        _canParticipate(lotId_, buyer_, callbackData_);

        // Call any additional implementation-specific logic
        __onBid(lotId_, bidId_, buyer_, amount_, callbackData_);
    }

    function __onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint96 amount_,
        bytes calldata callbackData_
    ) internal virtual {}

    function _onClaimProceeds(uint96, uint96, uint96, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _canParticipate(
        uint96 lotId_,
        address buyer_,
        bytes calldata callbackData_
    ) internal view virtual {
        // Decode the merkle proof from the callback data
        bytes32[] memory proof = abi.decode(callbackData_, (bytes32[]));

        // Get the leaf for the buyer
        bytes32 leaf = keccak256(abi.encodePacked(buyer_));

        // Validate the merkle proof
        if (!MerkleProofLib.verify(proof, lotMerkleRoot[lotId_], leaf)) {
            revert Callback_NotAuthorized();
        }
    }
}
