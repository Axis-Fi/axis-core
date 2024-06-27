// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {BALwithAllowlist} from "src/callbacks/liquidity/BaselineV2/BALwithAllowlist.sol";

/// @notice Capped allowlist version of the Baseline Axis Launch callback.
/// @notice This version allows for each address in the Merkle tree to have a standard amount of quote tokens they can spend.
contract BALwithCappedAllowlist is BALwithAllowlist {
    // ========== ERRORS ========== //

    /// @notice Error message when the bid amount exceeds the limit assigned to a buyer
    error Callback_ExceedsLimit();

    // ========== STATE VARIABLES ========== //

    /// @notice The maximum amount a buyer can spend
    uint256 public buyerLimit;

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
    ) BALwithAllowlist(auctionHouse_, baselineKernel_, reserve_, owner_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaselineAxisLaunch
    /// @dev        This function reverts if:
    ///             - `allowlistData_` is not of the correct length
    ///
    /// @param      allowlistData_ abi-encoded data: (bytes32) representing the merkle root
    function __onCreate(
        uint96,
        address,
        address,
        address,
        uint256,
        bool,
        bytes memory allowlistData_
    ) internal override {
        // Check that the parameters are of the correct length
        if (allowlistData_.length != 64) {
            revert Callback_InvalidParams();
        }

        // Decode the merkle root from the callback data
        (bytes32 merkleRoot_, uint256 buyerLimit_) = abi.decode(allowlistData_, (bytes32, uint256));

        // Revert if buyer limit is 0, should just use regular allowlist version
        if (buyerLimit_ == 0) revert Callback_InvalidParams();

        // Set the merkle root and buyer limit
        merkleRoot = merkleRoot_;
        buyerLimit = buyerLimit_;
        emit MerkleRootSet(merkleRoot);
    }

    /// @inheritdoc BALwithAllowlist
    /// @dev        This function reverts if:
    ///             - The buyer has already spent their limit
    function __onBid(
        uint96,
        uint64,
        address buyer_,
        uint256 amount_,
        bytes calldata
    ) internal override {
        // Validate that the buyer is allowed to participate
        _canBuy(buyer_, amount_);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _canBuy(address buyer_, uint256 amount_) internal {
        // Check if the buyer has already spent their limit
        if (buyerSpent[buyer_] + amount_ > buyerLimit) {
            revert Callback_ExceedsLimit();
        }

        // Update the buyer spent amount
        buyerSpent[buyer_] += amount_;
    }
}
