// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleAllowlist} from "src/callbacks/allowlists/MerkleAllowlist.sol";
import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @title  CappedMerkleAllowlist
/// @notice This contract extends the MerkleAllowlist contract to implement a merkle tree-based allowlist for buyers to participate in an auction.
///         In this implementation, each buyer has a purchase limit that is set for all buyers in an auction lot.
contract CappedMerkleAllowlist is MerkleAllowlist {
    // ========== ERRORS ========== //

    /// @notice Error message when the bid amount exceeds the limit assigned to a buyer
    error Callback_ExceedsLimit();

    // ========== STATE VARIABLES ========== //

    /// @notice Stores the purchase limit for each lot
    mapping(uint96 => uint256) public lotBuyerLimit;

    /// @notice Tracks the cumulative amount spent by a buyer on a lot
    mapping(uint96 => mapping(address => uint256)) public lotBuyerSpent;

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
    ///
    /// @param callbackData_    abi-encoded data: (bytes32, uint256) representing the merkle root and buyer limit
    function _onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal override {
        // Decode the merkle root from the callback data
        (bytes32 merkleRoot, uint256 buyerLimit) = abi.decode(callbackData_, (bytes32, uint256));

        // Set the merkle root and lot buyer limit
        lotMerkleRoot[lotId_] = merkleRoot;
        lotBuyerLimit[lotId_] = buyerLimit;
        emit MerkleRootSet(lotId_, merkleRoot);
    }

    /// @inheritdoc MerkleAllowlist
    function __onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256,
        bool,
        bytes calldata
    ) internal override {
        _canBuy(lotId_, buyer_, amount_);
    }

    /// @inheritdoc MerkleAllowlist
    function __onBid(
        uint96 lotId_,
        uint64,
        address buyer_,
        uint256 amount_,
        bytes calldata
    ) internal override {
        _canBuy(lotId_, buyer_, amount_);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _canBuy(uint96 lotId_, address buyer_, uint256 amount_) internal {
        // Check if the buyer has already spent their limit
        if (lotBuyerSpent[lotId_][buyer_] + amount_ > lotBuyerLimit[lotId_]) {
            revert Callback_ExceedsLimit();
        }

        // Update the buyer spent amount
        lotBuyerSpent[lotId_][buyer_] += amount_;
    }
}
