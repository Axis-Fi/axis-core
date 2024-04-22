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
    /// @param      recipient           Address to receive payout
    /// @param      referrer            Address of referrer
    /// @param      amount              Amount of quoteToken to purchase with (in native decimals)
    /// @param      auctionData         Custom data used by the auction module
    /// @param      permit2Data_        Permit2 approval for the quoteToken (abi-encoded Permit2Approval struct)
    struct BidParams {
        uint96 lotId;
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
    ///             3. Collect the payout from the seller (if not pre-funded)
    ///             4. If there is a partial fill, sends the refund and payout to the bidder
    ///             5. Send the fees to the curator
    ///
    /// @param      lotId_          Lot ID
    /// @return     totalIn_        Total amount of quote tokens from bids that were filled
    /// @return     totalOut_       Total amount of base tokens paid out to winning bids
    /// @return     auctionOutput_  Custom data returned by the auction module
    function settle(uint96 lotId_)
        external
        returns (uint256 totalIn_, uint256 totalOut_, bytes memory auctionOutput_);

    /// @notice     Claim the proceeds of a settled auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the lot
    ///             2. Pass the request to the auction module to get the proceeds data
    ///             3. Send the proceeds (quote tokens) to the seller
    ///             4. Refund any unused base tokens to the seller
    ///             5. Allocate the curator fee (base tokens) to the curator
    ///
    /// @param      lotId_          Lot ID
    /// @param      callbackData_   Custom data provided to the onClaimProceeds callback
    function claimProceeds(uint96 lotId_, bytes calldata callbackData_) external;
}
