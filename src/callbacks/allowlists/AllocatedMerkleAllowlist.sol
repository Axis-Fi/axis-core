// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProofLib} from "lib/solady/src/utils/MerkleProofLib.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";

contract AllocatedMerkleAllowlist is BaseCallback {
    // ========== ERRORS ========== //

    /// @notice Error message when the bid amount exceeds the limit assigned to a buyer
    error Callback_ExceedsLimit();

    /// @notice Error message when the callback state does not support the action
    error Callback_InvalidState();

    // ========== EVENTS ========== //

    /// @notice Emitted when the merkle root is set
    event MerkleRootSet(bytes32 merkleRoot);

    // ========== STATE VARIABLES ========== //

    /// @notice The root of the merkle tree that represents the allowlist for a lot
    mapping(uint96 lotId => bytes32 merkleRoot) public lotMerkleRoot;

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
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        _onBuy(lotId_, buyer_, amount_, callbackData_);
    }

    function _onBid(
        uint96 lotId_,
        uint64,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual override {
        _onBuy(lotId_, buyer_, amount_, callbackData_);
    }

    function _onBuy(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal {
        // Validate that the buyer is allowed to participate and get their allocated amount
        uint256 allocatedAmount = _canParticipate(lotId_, buyer_, callbackData_);

        // Validate that the buyer can spend the amount
        _canBuy(lotId_, buyer_, amount_, allocatedAmount);

        // Update the buyer's spent amount
        lotBuyerSpent[lotId_][buyer_] += amount_;
    }

    function _onSettle(uint96, uint256, uint256, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _canParticipate(
        uint96 lotId_,
        address buyer_,
        bytes calldata callbackData_
    ) internal view returns (uint256) {
        // Decode the merkle proof and allocated amount from buyer submitted callback data
        (bytes32[] memory proof, uint256 allocatedAmount) =
            abi.decode(callbackData_, (bytes32[], uint256));

        // Get the leaf for the buyer
        bytes32 leaf = keccak256(abi.encodePacked(buyer_, allocatedAmount));

        // Validate the merkle proof
        if (!MerkleProofLib.verify(proof, lotMerkleRoot[lotId_], leaf)) {
            revert Callback_NotAuthorized();
        }

        // Return the allocated amount
        return allocatedAmount;
    }

    function _canBuy(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 allocatedAmount_
    ) internal view {
        // Check if the buyer has already spent their limit
        if (lotBuyerSpent[lotId_][buyer_] + amount_ > allocatedAmount_) {
            revert Callback_ExceedsLimit();
        }
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Sets the merkle root for the allowlist
    ///         This function can be called by the owner to update the merkle root after `onCreate()`.
    /// @dev    This function performs the following:
    ///         - Performs validation
    ///         - Sets the merkle root
    ///         - Emits a MerkleRootSet event
    ///
    ///         This function reverts if:
    ///         - The caller is not the lot's owner
    ///         - The auction has not been registered
    ///         - The auction has been completed
    ///
    /// @param  merkleRoot_ The new merkle root
    function setMerkleRoot(uint96 lotId_, bytes32 merkleRoot_) external onlyRegisteredLot(lotId_) {
        // We check that the lot is registered on this callback

        // Check that the caller is the lot's owner
        (address seller,,,,,,,,) = IAuctionHouse(AUCTION_HOUSE).lotRouting(lotId_);
        if (msg.sender != seller) {
            revert Callback_NotAuthorized();
        }

        // Set the new merkle root and emit an event
        lotMerkleRoot[lotId_] = merkleRoot_;

        emit MerkleRootSet(merkleRoot_);
    }
}
