// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";

/// @notice Allowlist version of the Baseline Axis Launch callback.
/// @notice This version allows for a merkle tree to be used to determine which addresses are allowed to participate. However, the amount of quote tokens they can spend is not limited.
contract BALwithAllowlist is BaselineAxisLaunch {
    // ========== ERRORS ========== //

    /// @notice Error message when the callback state does not support the action
    error Callback_InvalidState();

    // ========== EVENTS ========== //

    /// @notice Emitted when the merkle root is set
    event MerkleRootSet(bytes32 merkleRoot);

    // ========== STATE VARIABLES ========== //

    /// @notice The root of the merkle tree that represents the allowlist
    /// @dev    The merkle tree should adhere to the format specified in the OpenZeppelin MerkleProof library at https://github.com/OpenZeppelin/merkle-tree
    ///         In particular, leaf values (such as `(address)` or `(address,uint256)`) should be double-hashed.
    bytes32 public merkleRoot;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: false
    // onBid: true
    // onSettle: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11101111 = 0xEF

    constructor(
        address auctionHouse_,
        address baselineKernel_,
        address reserve_,
        address owner_
    ) BaselineAxisLaunch(auctionHouse_, baselineKernel_, reserve_, owner_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaselineAxisLaunch
    /// @dev        This function reverts if:
    ///             - `allowlistData_` is not of the correct length
    ///
    /// @param      allowlistData_  abi-encoded data: (bytes32) representing the merkle root
    function __onCreate(
        uint96,
        address,
        address,
        address,
        uint256,
        bool,
        bytes memory allowlistData_
    ) internal virtual override {
        // Check that the parameters are of the correct length
        if (allowlistData_.length != 32) {
            revert Callback_InvalidParams();
        }

        // Decode the merkle root from the callback data
        bytes32 merkleRootParams = abi.decode(allowlistData_, (bytes32));

        // Set the merkle root
        merkleRoot = merkleRootParams;
        emit MerkleRootSet(merkleRoot);
    }

    /// @inheritdoc BaselineAxisLaunch
    ///
    /// @param      callbackData_   abi-encoded data: (bytes32[]) representing the merkle proof
    function _onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Validate that the buyer is allowed to participate
        _canParticipate(buyer_, callbackData_);

        // Call any additional implementation-specific logic
        __onBid(lotId_, bidId_, buyer_, amount_, callbackData_);
    }

    /// @notice Override this function to implement additional functionality for the `onBid` callback
    ///
    /// @param  lotId_          The ID of the lot
    /// @param  bidId_          The ID of the bid
    /// @param  buyer_          The address of the buyer
    /// @param  amount_         The amount of quote tokens
    /// @param  callbackData_   The callback data
    function __onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual {}

    // ========== INTERNAL FUNCTIONS ========== //

    function _canParticipate(address buyer_, bytes calldata callbackData_) internal view {
        // Decode the merkle proof from the callback data
        bytes32[] memory proof = abi.decode(callbackData_, (bytes32[]));

        // Get the leaf for the buyer
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(buyer_))));

        // Validate the merkle proof
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) {
            revert Callback_NotAuthorized();
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
    ///         - The caller is not the owner
    ///         - The auction has not been registered
    ///         - The auction has been completed
    ///
    /// @param  merkleRoot_ The new merkle root
    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        // Revert if onCreate has not been called
        if (lotId == type(uint96).max) {
            revert Callback_InvalidState();
        }

        // Revert if the auction has been completed already
        if (auctionComplete) {
            revert Callback_InvalidState();
        }

        merkleRoot = merkleRoot_;

        emit MerkleRootSet(merkleRoot_);
    }
}
