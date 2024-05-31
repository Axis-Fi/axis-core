// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";

/// @title  MerkleAllowlist
/// @notice This contract implements a merkle tree-based allowlist for buyers to participate in an auction.
///         In this implementation, buyers do not have a limit on the amount they can purchase/bid.
contract MerkleAllowlist is BaseCallback {
    // ========== EVENTS ========== //

    /// @notice Emitted when the merkle root is set
    event MerkleRootSet(uint96 lotId, bytes32 merkleRoot);

    // ========== STATE VARIABLES ========== //

    /// @notice The root of the merkle tree that represents the allowlist for a lot
    /// @dev    The merkle tree should adhere to the format specified in the OpenZeppelin MerkleProof library at https://github.com/OpenZeppelin/merkle-tree
    ///         In particular, leaf values (such as `(address)` or `(address,uint256)`) should be double-hashed.
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

    /// @inheritdoc BaseCallback
    /// @dev        This function performs the following:
    ///             - Validates the callback data
    ///             - Sets the merkle root
    ///             - Emits a MerkleRootSet event
    ///
    ///             This function reverts if:
    ///             - The callback data is of an invalid length
    ///
    /// @param      lotId_          The id of the lot
    /// @param      callbackData_   abi-encoded callback data - a single bytes32 value representing the merkle root
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
        emit MerkleRootSet(lotId_, merkleRoot);
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onCancel(uint96, uint256, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onCurate(uint96, uint256, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        This function performs the following:
    ///             - Validates that the buyer is allowed to participate
    ///             - Calls any additional implementation-specific logic
    ///
    ///             This function reverts if:
    ///             - The buyer is not allowed to participate
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

    /// @notice Additional implementation-specific logic for the purchase callback
    /// @dev    This function can be overridden by an inheriting contract to implement additional logic
    ///
    /// @param  lotId_          The id of the lot
    /// @param  buyer_          The address of the buyer
    /// @param  amount_         The amount of quote tokens sent
    /// @param  payout_         The amount of base tokens to be sent
    /// @param  prefunded_      Whether the lot is prefunded
    /// @param  callbackData_   abi-encoded callback data
    function __onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual {}

    /// @inheritdoc BaseCallback
    /// @dev        This function performs the following:
    ///             - Validates that the buyer is allowed to participate
    ///             - Calls any additional implementation-specific logic
    ///
    ///             This function reverts if:
    ///             - The buyer is not allowed to participate
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

    /// @notice Additional implementation-specific logic for the bid callback
    /// @dev    This function can be overridden by an inheriting contract to implement additional logic
    function __onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual {}

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
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
