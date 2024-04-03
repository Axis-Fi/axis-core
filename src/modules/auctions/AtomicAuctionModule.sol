// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Auction, AuctionModule} from "src/modules/Auction.sol";

abstract contract AtomicAuctionModule is AuctionModule {
    // ========== SETUP ========== //

    /// @inheritdoc Auction
    function auctionType() external pure override returns (AuctionType) {
        return AuctionType.Atomic;
    }

    // ========== ATOMIC AUCTIONS ========== //

    /// @inheritdoc Auction
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
        uint96 amount_,
        bytes calldata auctionData_
    ) external override onlyInternal returns (uint96 payout, bytes memory auctionOutput) {
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
        uint96 amount_,
        bytes calldata auctionData_
    ) internal virtual returns (uint96 payout, bytes memory auctionOutput);

    // ========== NOT IMPLEMENTED ========== //

    function bid(
        uint96,
        address,
        address,
        uint96,
        bytes calldata
    ) external virtual override returns (uint64) {
        revert Auction_NotImplemented();
    }

    function refundBid(uint96, uint64, address) external virtual override returns (uint96) {
        revert Auction_NotImplemented();
    }

    function claimBids(
        uint96,
        uint64[] calldata
    ) external virtual override returns (BidClaim[] memory, bytes memory) {
        revert Auction_NotImplemented();
    }

    function settle(uint96) external virtual override returns (Settlement memory, bytes memory) {
        revert Auction_NotImplemented();
    }

    function claimProceeds(uint96) external virtual override returns (uint96, uint96, uint96) {
        revert Auction_NotImplemented();
    }
}
