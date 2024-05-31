// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";

contract MerkleAllowlist is BaseCallback {
    // ========== EVENTS ========== //

    /// @notice Emitted when the merkle root is set
    event MerkleRootSet(uint96 lotId, bytes32 merkleRoot);

    // ========== STATE VARIABLES ========== //

    /// @notice The root of the merkle tree that represents the allowlist for a lot
    mapping(uint96 lotId => bytes32 merkleRoot) public lotMerkleRoot;

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
    ) BaseCallback(auctionHouse_, permissions_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    function _onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        // Check that the parameters are of the correct length
        if (callbackData_.length != 32) {
            revert Callback_InvalidParams();
        }

        // Decode the merkle root from the callback data
        bytes32 merkleRoot = abi.decode(callbackData_, (bytes32));

        // Set the merkle root
        lotMerkleRoot[lotId_] = merkleRoot;
    }

    function _onCancel(uint96, uint256, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onCurate(uint96, uint256, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 payout_,
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
        uint256 amount_,
        uint256 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual {}

    function _onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
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
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual {}

    function _onSettle(uint96, uint256, uint256, bytes calldata) internal pure override {
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
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(buyer_))));

        // Validate the merkle proof
        if (!MerkleProof.verify(proof, lotMerkleRoot[lotId_], leaf)) {
            revert Callback_NotAuthorized();
        }
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Sets the merkle root for the allowlist
    ///         This function can be called by the lot's seller to update the merkle root after `onCreate()`.
    /// @dev    This function performs the following:
    ///         - Performs validation
    ///         - Sets the merkle root
    ///         - Emits a MerkleRootSet event
    ///
    ///         This function reverts if:
    ///         - The caller is not the lot's seller
    ///         - The auction has not been registered
    ///
    /// @param  merkleRoot_ The new merkle root
    function setMerkleRoot(uint96 lotId_, bytes32 merkleRoot_) external onlyRegisteredLot(lotId_) {
        // We check that the lot is registered on this callback

        // Check that the caller is the lot's seller
        (address seller,,,,,,,,) = IAuctionHouse(AUCTION_HOUSE).lotRouting(lotId_);
        if (msg.sender != seller) {
            revert Callback_NotAuthorized();
        }

        // Set the new merkle root and emit an event
        lotMerkleRoot[lotId_] = merkleRoot_;

        emit MerkleRootSet(lotId_, merkleRoot_);
    }
}
