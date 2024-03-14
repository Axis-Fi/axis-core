// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleAllowlist} from "src/callbacks/allowlists/MerkleAllowlist.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

contract CappedMerkleAllowlist is MerkleAllowlist {
    // ========== ERRORS ========== //
    error Callback_ExceedsLimit();

    // ========== STATE VARIABLES ========== //

    mapping(uint96 => uint96) public lotBuyerLimit;
    mapping(uint96 => mapping(address => uint96)) public lotBuyerSpent;

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
    ) MerkleAllowlist(auctionHouse_, permissions_, seller_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    function _onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint96,
        bool,
        bytes calldata callbackData_
    ) internal override {
        // Decode the merkle root from the callback data
        (bytes32 merkleRoot, uint96 buyerLimit) = abi.decode(callbackData_, (bytes32, uint96));

        // Set the merkle root and lot buyer limit
        lotMerkleRoot[lotId_] = merkleRoot;
        lotBuyerLimit[lotId_] = buyerLimit;
    }

    function __onPurchase(
        uint96 lotId_,
        address buyer_,
        uint96 amount_,
        uint96,
        bool,
        bytes calldata
    ) internal override {
        _canBuy(lotId_, buyer_, amount_);
    }

    function __onBid(
        uint96 lotId_,
        uint64,
        address buyer_,
        uint96 amount_,
        bytes calldata
    ) internal override {
        _canBuy(lotId_, buyer_, amount_);
    }

    // ========== INTERNAL FUNCTIONS ========== //
    function _canBuy(uint96 lotId_, address buyer_, uint96 amount_) internal {
        // Check if the buyer has already spent their limit
        if (lotBuyerSpent[lotId_][buyer_] + amount_ > lotBuyerLimit[lotId_]) {
            revert Callback_ExceedsLimit();
        }

        // Update the buyer spent amount
        lotBuyerSpent[lotId_][buyer_] += amount_;
    }
}
