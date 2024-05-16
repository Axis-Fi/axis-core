// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";

/// @title      IBatchAuctionHouse
/// @notice     An interface to define the BatchAuctionHouse's buyer-facing functions
interface IBatchAuctionHouse is IAuctionHouse {
    // ========== DATA STRUCTURES ========== //

    /// @notice     Parameters used by the bid function
    /// @dev        This reduces the number of variables in scope for the bid function
    ///
    /// @param      lotId               Lot ID
    /// @param      bidder              Address to receive refunds and payouts (if not zero address)
    /// @param      referrer            Address of referrer
    /// @param      amount              Amount of quoteToken to purchase with (in native decimals)
    /// @param      auctionData         Custom data used by the auction module
    /// @param      permit2Data_        Permit2 approval for the quoteToken (abi-encoded Permit2Approval struct)
    struct BidParams {
        uint96 lotId;
        address bidder;
        address referrer;
        uint256 amount;
        bytes auctionData;
        bytes permit2Data;
    }

    // ========== BATCH AUCTIONS ========== //

    /// @notice     Bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Store the bid
    ///             3. Transfer the amount of quote token from the bidder
    ///
    /// @param      params_         Bid parameters
    /// @param      callbackData_   Custom data provided to the onBid callback
    /// @return     bidId           Bid ID
    function bid(
        BidParams memory params_,
        bytes calldata callbackData_
    ) external returns (uint64 bidId);

    /// @notice     Refund a bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Pass the request to the auction module to validate and update data
    ///             3. Send the refund to the bidder
    ///
    /// @param      lotId_          Lot ID
    /// @param      bidId_          Bid ID
    /// @param      index_          Index of the bid in the auction's bid list
    function refundBid(uint96 lotId_, uint64 bidId_, uint256 index_) external;

    /// @notice     Claim bid payouts and/or refunds after a batch auction has settled
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the lot ID
    ///             2. Pass the request to the auction module to validate and update bid data
    ///             3. Send the refund and/or payout to the bidders
    ///
    /// @param      lotId_          Lot ID
    /// @param      bidIds_         Bid IDs
    function claimBids(uint96 lotId_, uint64[] calldata bidIds_) external;

    /// @notice     Settle a batch auction
    /// @notice     This function is used for versions with on-chain storage of bids and settlement
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the lot
    ///             2. Pass the request to the auction module to calculate winning bids
    ///             If settlement is completed:
    ///             3. Send the proceeds (quote tokens) to the seller
    ///             4. Execute the onSettle callback
    ///             5. Refund any unused base tokens to the seller
    ///             6. Allocate the curator fee (base tokens) to the curator
    ///
    /// @param      lotId_          Lot ID
    /// @param      num_            Number of bids to settle in this pass (capped at the remaining number if more is provided)
    /// @param      callbackData_   Custom data provided to the onSettle callback
    /// @return     totalIn         Total amount of quote tokens from bids that were filled
    /// @return     totalOut        Total amount of base tokens paid out to winning bids
    /// @return     finished        Boolean indicating if the settlement was completed
    /// @return     auctionOutput   Custom data returned by the auction module
    function settle(
        uint96 lotId_,
        uint256 num_,
        bytes calldata callbackData_
    )
        external
        returns (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput);

    /// @notice    Abort a batch auction that cannot be settled, refunding the seller and allowing bidders to claim refunds
    /// @dev       This function can be called by anyone. Care should be taken to ensure proper logic is in place to prevent calling when not desired.
    /// @dev       The implementing function should handle the following:
    ///            1. Validate the lot
    ///            2. Pass the request to the auction module to update the lot data
    ///            3. Refund the seller
    ///
    /// @param     lotId_    The lot id
    function abort(uint96 lotId_) external;
}
