// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {IBatchAuction} from "../IBatchAuction.sol";

/// @notice Interface for fixed price batch auctions
interface IFixedPriceBatch is IBatchAuction {
    // ========== ERRORS ========== //

    error Auction_WrongState(uint96 lotId);
    error Bid_WrongState(uint96 lotId, uint64 bidId);
    error NotPermitted(address caller);

    // ========== DATA STRUCTURES ========== //

    /// @notice     The status of an auction lot
    enum LotStatus {
        Created,
        Settled
    }

    /// @notice     The status of a bid
    /// @dev        Bid status will also be set to claimed if the bid is cancelled/refunded
    enum BidStatus {
        Submitted,
        Claimed
    }

    /// @notice Parameters for a fixed price auction
    ///
    /// @param  price            The fixed price of the lot
    /// @param  minFillPercent   The minimum percentage of the lot that must be filled in order to settle (100% = 100e2 = 1e4)
    struct AuctionDataParams {
        uint256 price;
        uint24 minFillPercent;
    }

    /// @notice Core data for an auction lot
    ///
    /// @param  price              The price of the lot
    /// @param  status             The status of the lot
    /// @param  nextBidId          The ID of the next bid
    /// @param  settlementCleared  True if the settlement has been cleared
    /// @param  totalBidAmount     The total amount of all bids
    /// @param  minFilled          The minimum amount of the lot that must be filled in order to settle
    struct AuctionData {
        uint256 price; // 32 - slot 1
        LotStatus status; // 1 +
        uint64 nextBidId; // 8 +
        bool settlementCleared; // 1 = 10 - end of slot 2
        uint256 totalBidAmount; // 32 - slot 3
        uint256 minFilled; // 32 - slot 4
    }

    /// @notice        Core data for a bid
    ///
    /// @param         bidder              The address of the bidder
    /// @param         amount              The amount of the bid
    /// @param         referrer            The address of the referrer
    /// @param         status              The status of the bid
    struct Bid {
        address bidder; // 20 +
        uint96 amount; // 12 = 32 - end of slot 1
        address referrer; // 20 +
        BidStatus status; // 1 = 21 - end of slot 2
    }

    /// @notice        Struct containing partial fill data for a lot
    ///
    /// @param         bidId        The ID of the bid
    /// @param         refund       The amount to refund to the bidder
    /// @param         payout       The amount to payout to the bidder
    struct PartialFill {
        uint64 bidId; // 8 +
        uint96 refund; // 12 = 20 - end of slot 1
        uint256 payout; // 32 - slot 2
    }

    // ========== AUCTION INFORMATION ========== //

    /// @notice Returns the `Bid` and `EncryptedBid` data for a given lot and bid ID
    ///
    /// @param  lotId_          The lot ID
    /// @param  bidId_          The bid ID
    /// @return bid             The `Bid` data
    function getBid(uint96 lotId_, uint64 bidId_) external view returns (Bid memory bid);

    /// @notice Returns the `AuctionData` data for an auction lot
    ///
    /// @param  lotId_          The lot ID
    /// @return auctionData_    The `AuctionData`
    function getAuctionData(
        uint96 lotId_
    ) external view returns (AuctionData memory auctionData_);

    /// @notice Returns the `PartialFill` data for an auction lot
    ///
    /// @param  lotId_          The lot ID
    /// @return hasPartialFill  True if a partial fill exists
    /// @return partialFill     The `PartialFill` data
    function getPartialFill(
        uint96 lotId_
    ) external view returns (bool hasPartialFill, PartialFill memory partialFill);
}
