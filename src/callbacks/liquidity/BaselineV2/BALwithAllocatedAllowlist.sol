// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProofLib} from "lib/solady/src/utils/MerkleProofLib.sol";

import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";

/// @notice Allocated allowlist version of the Baseline Axis Launch callback for batch auctions.
/// @notice This version allows for each address in the Merkle tree to have a per-address amount of quote tokens they can spend.
/// @dev    The merkle tree is expected to have both an address and an amount of quote tokens they can spend in each leaf.
contract BALwithAllocatedAllowlist is BaselineAxisLaunch {
    // ========== ERRORS ========== //

    /// @notice Error message when the bid amount exceeds the limit assigned to a buyer
    error Callback_ExceedsLimit();

    /// @notice Error message when the callback state does not support the action
    error Callback_InvalidState();

    // ========== EVENTS ========== //

    /// @notice Emitted when the merkle root is set
    event MerkleRootSet(bytes32 merkleRoot);

    // ========== DATA STRUCTURES ========== //

    /// @notice The parameters for creating an allocated allowlist
    /// @dev    The merkle tree from which the merkle root is generated is expected to be made up of leaves with the following structure:
    ///         keccak256(abi.encodePacked(address, uint256))
    ///
    /// @param  merkleRoot The root of the merkle tree. Can be updated later by the owner using `setMerkleRoot()`.
    struct AllocatedAllowlistCreateParams {
        bytes32 merkleRoot;
    }

    /// @notice The parameters for bidding with an allocated allowlist
    ///
    /// @param  proof           The merkle proof for the buyer
    /// @param  allocatedAmount The total amount the buyer is allowed to spend
    struct AllocatedAllowlistBidParams {
        bytes32[] proof;
        uint256 allocatedAmount;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice The root of the merkle tree that represents the allowlist
    bytes32 public merkleRoot;

    /// @notice Tracks the cumulative amount spent by a buyer
    mapping(address => uint256) public buyerSpent;

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
    /// @param      allowlistData_ abi-encoded AllocatedAllowlistCreateParams
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
        AllocatedAllowlistCreateParams memory allowlistParams =
            abi.decode(allowlistData_, (AllocatedAllowlistCreateParams));

        // Set the merkle root and buyer limit
        merkleRoot = allowlistParams.merkleRoot;
    }

    /// @inheritdoc BaselineAxisLaunch
    function _onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Validate that the buyer is allowed to participate
        uint256 allocatedAmount = _canParticipate(buyer_, callbackData_);

        // Validate that the buyer can buy the amount
        _canBuy(buyer_, amount_, allocatedAmount);

        // Call any additional implementation-specific logic
        __onBid(lotId_, bidId_, buyer_, amount_, callbackData_);
    }

    /// @notice Override this function to implement additional functionality
    function __onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual {}

    // ========== INTERNAL FUNCTIONS ========== //

    /// @dev The buyer must provide the proof and their total allocated amount in the callback data for this to succeed.
    function _canParticipate(
        address buyer_,
        bytes calldata callbackData_
    ) internal view returns (uint256) {
        // Decode the merkle proof from the callback data
        AllocatedAllowlistBidParams memory bidParams =
            abi.decode(callbackData_, (AllocatedAllowlistBidParams));

        // Get the leaf for the buyer
        bytes32 leaf = keccak256(abi.encodePacked(buyer_, bidParams.allocatedAmount));

        // Validate the merkle proof
        if (!MerkleProofLib.verify(bidParams.proof, merkleRoot, leaf)) {
            revert Callback_NotAuthorized();
        }

        // Return the allocated amount for the buyer
        return bidParams.allocatedAmount;
    }

    function _canBuy(address buyer_, uint256 amount_, uint256 allocatedAmount_) internal {
        // Check if the buyer has already spent their limit
        if (buyerSpent[buyer_] + amount_ > allocatedAmount_) {
            revert Callback_ExceedsLimit();
        }

        // Update the buyer spent amount
        buyerSpent[buyer_] += amount_;
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
