// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {IAuction} from "src/interfaces/IAuction.sol";

/// @title  IBatchAuction
/// @notice Interface for batch auctions
/// @dev    The implementing contract should define the following additional areas:
///         - Any un-implemented functions
///         - State variables for storage and configuration
interface IBatchAuction is IAuction {
    // ========== ERRORS ========== //

    error Auction_DedicatedSettlePeriod(uint96 lotId);
    error Auction_InvalidBidId(uint96 lotId, uint96 bidId);
    error Auction_NotBidder();

    // ========== DATA STRUCTURES ========== //

    /// @notice Contains data about a bidder's outcome from an auction
    /// @dev    Only used in memory so doesn't need to be packed
    ///
    /// @param  bidder   The bidder
    /// @param  referrer The referrer
    /// @param  paid     The amount of quote tokens paid (including any refunded tokens)
    /// @param  payout   The amount of base tokens paid out
    /// @param  refund   The amount of quote tokens refunded
    struct BidClaim {
        address bidder;
        address referrer;
        uint256 paid;
        uint256 payout;
        uint256 refund;
    }

    // ========== BATCH OPERATIONS ========== //

    /// @notice     Bid on an auction lot
    /// @dev        The implementing function should handle the following:
    ///             - Validate the bid parameters
    ///             - Store the bid data
    ///
    /// @param      lotId_          The lot id
    /// @param      bidder_         The bidder of the purchased tokens
    /// @param      referrer_       The referrer of the bid
    /// @param      amount_         The amount of quote tokens to bid
    /// @param      auctionData_    The auction-specific data
    /// @return     bidId           The bid id
    function bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external returns (uint64 bidId);

    /// @notice     Refund a bid
    /// @dev        The implementing function should handle the following:
    ///             - Validate the bid parameters
    ///             - Authorize `caller_`
    ///             - Update the bid data
    ///
    /// @param      lotId_      The lot id
    /// @param      bidId_      The bid id
    /// @param      index_      The index of the bid ID in the auction's bid list
    /// @param      caller_     The caller
    /// @return     refund      The amount of quote tokens to refund
    function refundBid(
        uint96 lotId_,
        uint64 bidId_,
        uint256 index_,
        address caller_
    ) external returns (uint256 refund);

    /// @notice     Claim multiple bids
    /// @dev        The implementing function should handle the following:
    ///             - Validate the bid parameters
    ///             - Update the bid data
    ///
    /// @param      lotId_          The lot id
    /// @param      bidIds_         The bid ids
    /// @return     bidClaims       The bid claim data
    /// @return     auctionOutput   The auction-specific output
    function claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    ) external returns (BidClaim[] memory bidClaims, bytes memory auctionOutput);

    /// @notice     Settle a batch auction lot with on-chain storage and settlement
    /// @dev        The implementing function should handle the following:
    ///             - Validate the lot parameters
    ///             - Determine the winning bids
    ///             - Update the lot data
    ///
    /// @param      lotId_          The lot id
    /// @param      num_            The number of winning bids to settle (capped at the remaining number if more is provided)
    /// @return     totalIn         Total amount of quote tokens from bids that were filled
    /// @return     totalOut        Total amount of base tokens paid out to winning bids
    /// @return     capacity        The original capacity of the lot
    /// @return     finished        Whether the settlement is finished
    /// @return     auctionOutput   Custom data returned by the auction module
    function settle(
        uint96 lotId_,
        uint256 num_
    )
        external
        returns (
            uint256 totalIn,
            uint256 totalOut,
            uint256 capacity,
            bool finished,
            bytes memory auctionOutput
        );

    /// @notice    Abort a batch auction that cannot be settled, refunding the seller and allowing bidders to claim refunds
    /// @dev       The implementing function should handle the following:
    ///            - Validate the lot is in the correct state
    ///            - Set the auction in a state that allows bidders to claim refunds
    ///
    /// @param     lotId_    The lot id
    function abort(uint96 lotId_) external;

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Get the number of bids for a lot
    ///
    /// @param  lotId_  The lot ID
    /// @return         The number of bids
    function getNumBids(uint96 lotId_) external view returns (uint256);

    /// @notice Get the bid IDs from the given index
    ///
    /// @param  lotId_  The lot ID
    /// @param  start_  The index to start retrieving bid IDs from
    /// @param  count_  The number of bids to retrieve
    /// @return         The bid IDs
    function getBidIds(
        uint96 lotId_,
        uint256 start_,
        uint256 count_
    ) external view returns (uint64[] memory);

    /// @notice Get the bid ID at the given index
    ///
    /// @param  lotId_  The lot ID
    /// @param  index_  The index
    /// @return         The bid ID
    function getBidIdAtIndex(uint96 lotId_, uint256 index_) external view returns (uint64);

    /// @notice Get the claim data for a bid
    /// @notice This provides information on the outcome of a bid, independent of the claim status
    ///
    /// @param  lotId_  The lot ID
    /// @param  bidId_  The bid ID
    /// @return         The bid claim data
    function getBidClaim(uint96 lotId_, uint64 bidId_) external view returns (BidClaim memory);
}
