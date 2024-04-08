// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Auction, AuctionModule} from "src/modules/Auction.sol";

abstract contract AtomicAuction {
    // ========== ATOMIC AUCTIONS ========== //

    /// @notice     Purchase tokens from an auction lot
    /// @dev        The implementing function should handle the following:
    ///             - Validate the purchase parameters
    ///             - Store the purchase data
    ///
    /// @param      lotId_             The lot id
    /// @param      amount_         The amount of quote tokens to purchase
    /// @param      auctionData_    The auction-specific data
    /// @return     payout          The amount of payout tokens to receive
    /// @return     auctionOutput   The auction-specific output
    function purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external virtual returns (uint256 payout, bytes memory auctionOutput);

    // ========== VIEW FUNCTIONS ========== //

    function payoutFor(uint96 lotId_, uint256 amount_) public view virtual returns (uint256) {}

    function priceFor(uint96 lotId_, uint256 payout_) public view virtual returns (uint256) {}

    function maxPayout(uint96 lotId_) public view virtual returns (uint256) {}

    function maxAmountAccepted(uint96 lotId_) public view virtual returns (uint256) {}
}

/// @title  Atomic Auction Module
/// @notice A base contract for atomic auctions
abstract contract AtomicAuctionModule is AtomicAuction, AuctionModule {
    // ========== ATOMIC AUCTIONS ========== //

    /// @inheritdoc AtomicAuction
    /// @dev        Implements a basic purchase function that:
    ///             - Calls implementation-specific validation logic
    ///             - Calls the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot is inactive
    ///             - the caller is not an internal module
    ///             - the payout is greater than the remaining capacity
    ///
    ///             Inheriting contracts should override _purchase to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Storing the purchase data
    function purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external override onlyInternal returns (uint256 payout, bytes memory auctionOutput) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotInactive(lotId_);

        // Call implementation-specific logic
        (payout, auctionOutput) = _purchase(lotId_, amount_, auctionData_);

        // Update capacity
        Lot storage lot = lotData[lotId_];
        // Revert if the capacity is insufficient
        if (lot.capacityInQuote ? amount_ > lot.capacity : payout > lot.capacity) {
            revert Auction_InsufficientCapacity();
        }
        unchecked {
            lot.capacity -= lot.capacityInQuote ? amount_ : payout;
        }

        // Update the purchased and sold amounts for the lot
        lot.purchased += amount_;
        lot.sold += payout;
    }

    /// @notice     Implementation-specific purchase logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_          The lot ID
    /// @param      amount_         The amount of quote tokens to purchase
    /// @param      auctionData_    The auction-specific data
    /// @return     payout          The amount of payout tokens to receive
    /// @return     auctionOutput   The auction-specific output
    function _purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal virtual returns (uint256 payout, bytes memory auctionOutput);
}
