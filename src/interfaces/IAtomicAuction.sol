// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {IAuction} from "src/interfaces/IAuction.sol";

/// @title  IAtomicAuction
/// @notice Interface for atomic auctions
/// @dev    The implementing contract should define the following additional areas:
///         - Any un-implemented functions
///         - State variables for storage and configuration
interface IAtomicAuction is IAuction {
    // ========== ATOMIC AUCTIONS ========== //

    /// @notice     Purchase tokens from an auction lot
    /// @dev        The implementing function should handle the following:
    ///             - Validate the purchase parameters
    ///             - Store the purchase data
    ///
    /// @param      lotId_          The lot id
    /// @param      amount_         The amount of quote tokens to purchase
    /// @param      auctionData_    The auction-specific data
    /// @return     payout          The amount of payout tokens to receive
    /// @return     auctionOutput   The auction-specific output
    function purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external returns (uint256 payout, bytes memory auctionOutput);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice     Returns the payout for a given lot and amount
    function payoutFor(uint96 lotId_, uint256 amount_) external view returns (uint256 payout);

    /// @notice     Returns the price for a given lot and payout
    function priceFor(uint96 lotId_, uint256 payout_) external view returns (uint256 price);

    /// @notice     Returns the max payout for a given lot
    function maxPayout(uint96 lotId_) external view returns (uint256 payout);

    /// @notice     Returns the max amount of quote tokens that can be accepted for a given lot
    function maxAmountAccepted(uint96 lotId_) external view returns (uint256 maxAmount);
}
