// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProofLib} from "lib/solady/src/utils/MerkleProofLib.sol";

import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @notice Allocated allowlist version of the Baseline Axis Launch callback.
/// @notice This version allows for each address in the Merkle tree to have a per-address amount of quote tokens they can spend.
/// @dev    The merkle tree is expected to have both an address and an amount of quote tokens they can spend in each leaf.
contract BALwithAllocatedAllowlist is BaselineAxisLaunch {
    // ========== ERRORS ========== //
    error Callback_ExceedsLimit();

    // ========== STATE VARIABLES ========== //

    bytes32 public merkleRoot;
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
        Callbacks.Permissions memory permissions_,
        address baselineKernel_,
        address reserve_
    ) BaselineAxisLaunch(auctionHouse_, permissions_, baselineKernel_, reserve_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    function __onCreate(
        uint96,
        address,
        address,
        address,
        uint256,
        bool,
        bytes memory allowlistData_
    ) internal virtual override {
        // Decode the merkle root from the callback data
        (bytes32 merkleRoot_) = abi.decode(allowlistData_, (bytes32));

        // Set the merkle root and buyer limit
        merkleRoot = merkleRoot_;
    }

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
        (bytes32[] memory proof, uint256 allocatedAmount) =
            abi.decode(callbackData_, (bytes32[], uint256));

        // Get the leaf for the buyer
        bytes32 leaf = keccak256(abi.encodePacked(buyer_, allocatedAmount));

        // Validate the merkle proof
        if (!MerkleProofLib.verify(proof, merkleRoot, leaf)) {
            revert Callback_NotAuthorized();
        }

        // Return the allocated amount for the buyer
        return allocatedAmount;
    }

    // ========== INTERNAL FUNCTIONS ========== //
    function _canBuy(address buyer_, uint256 amount_, uint256 allocatedAmount_) internal {
        // Check if the buyer has already spent their limit
        if (buyerSpent[buyer_] + amount_ > allocatedAmount_) {
            revert Callback_ExceedsLimit();
        }

        // Update the buyer spent amount
        buyerSpent[buyer_] += amount_;
    }
}
