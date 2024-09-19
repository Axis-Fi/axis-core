// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IBatchAuction} from "../../../interfaces/modules/IBatchAuction.sol";
import {IFixedPriceBatch} from "../../../interfaces/modules/auctions/IFixedPriceBatch.sol";

// External libraries
import {FixedPointMathLib as Math} from "@solady-0.0.124/utils/FixedPointMathLib.sol";

// Auctions
import {AuctionModule} from "../../Auction.sol";
import {BatchAuctionModule} from "../BatchAuctionModule.sol";

import {Module, Veecode, toVeecode} from "../../Modules.sol";

/// @title  FixedPriceBatch
/// @notice A module for creating fixed price batch auctions
contract FixedPriceBatch is BatchAuctionModule, IFixedPriceBatch {
    // ========== STATE VARIABLES ========== //

    /// @notice     FPBA-specific auction data for a lot
    /// @dev        Access via `getAuctionData()`
    mapping(uint96 lotId => AuctionData) internal _auctionData;

    /// @notice     General information about bids on a lot
    /// @dev        Access via `getBid()`
    mapping(uint96 lotId => mapping(uint64 bidId => Bid)) internal _bids;

    /// @notice     Partial fill data for a lot
    /// @dev        Each FPBA can have at most one partial fill
    ///             Access via `getPartialFill()`
    mapping(uint96 lotId => PartialFill) internal _lotPartialFill;

    // ========== SETUP ========== //

    constructor(
        address auctionHouse_
    ) AuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day initially
        minAuctionDuration = 1 days;

        // Set the dedicated settle period to 1 day initially
        dedicatedSettlePeriod = 1 days;
    }

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01FPBA");
    }

    // ========== AUCTION ========== //

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes:
    ///             - The lot ID has been validated
    ///             - The start and duration of the lot have been validated
    ///
    ///             This function reverts if:
    ///             - The parameters cannot be decoded into the correct format
    ///             - The price is zero
    ///             - The minimum fill percentage is greater than
    ///
    /// @param      params_    ABI-encoded data of type `AuctionDataParams`
    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override {
        // Decode the auction params
        AuctionDataParams memory params = abi.decode(params_, (AuctionDataParams));

        // Validate the price is not zero
        if (params.price == 0) revert Auction_InvalidParams();

        // minFillPercent must be less than or equal to 100%
        if (params.minFillPercent > _ONE_HUNDRED_PERCENT) revert Auction_InvalidParams();

        // Set the auction data
        AuctionData storage data = _auctionData[lotId_];
        data.price = params.price;
        data.nextBidId = 1;
        // data.status = LotStatus.Created; // Set by default
        // data.totalBidAmount = 0; // Set by default
        // We round up to be conservative with the minimums
        data.minFilled =
            Math.fullMulDivUp(lot_.capacity, params.minFillPercent, _ONE_HUNDRED_PERCENT);
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes the following:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction has not concluded
    ///
    ///             This function performs the following:
    ///             - Sets the auction status to settled, and prevents claiming of proceeds
    ///
    ///             This function reverts if:
    ///             - The auction is active or has not concluded
    function _cancelAuction(
        uint96 lotId_
    ) internal override {
        // Validation
        // Batch auctions cannot be cancelled once started, otherwise the seller could cancel the auction after bids have been submitted
        _revertIfLotActive(lotId_);

        // Set auction status to settled
        // No bids could have been submitted at this point so there will not be any claimed
        _auctionData[lotId_].status = LotStatus.Settled;
    }

    // ========== BID ========== //

    function _calculatePartialFill(
        uint64 bidId_,
        uint256 capacity_,
        uint256 capacityExpended_,
        uint96 bidAmount_,
        uint256 baseScale_,
        uint256 price_
    ) internal pure returns (PartialFill memory) {
        // Calculate the bid payout if it were fully filled
        uint256 fullFill = Math.fullMulDiv(bidAmount_, baseScale_, price_);
        uint256 excess = capacityExpended_ - capacity_;

        // Refund will be within the bounds of uint96
        // bidAmount is uint96, excess < fullFill, so bidAmount * excess / fullFill < bidAmount < uint96 max
        uint96 refund = uint96(Math.fullMulDiv(bidAmount_, excess, fullFill));
        uint256 payout = fullFill - excess;

        return (PartialFill({bidId: bidId_, refund: refund, payout: payout}));
    }

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Stores the bid
    ///             - Conditionally ends the auction if the bid fills the lot (bid may be partial fill)
    ///             - Returns the bid ID
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is active
    ///
    ///             This function reverts if:
    ///             - Amount is zero
    ///             - Amount is greater than the maximum uint96
    function _bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint256 amount_,
        bytes calldata
    ) internal override returns (uint64) {
        // Amount cannot be zero or greater than the maximum uint96
        if (amount_ == 0 || amount_ > type(uint96).max) revert Auction_InvalidParams();

        // Load the lot and auction data
        uint256 lotCapacity = lotData[lotId_].capacity;
        AuctionData storage data = _auctionData[lotId_];

        // Get the bid ID and increment the next bid ID
        uint64 bidId = data.nextBidId++;

        // Has already been checked to be in bounds
        uint96 amount96 = uint96(amount_);

        // Store the bid
        _bids[lotId_][bidId] = Bid({
            bidder: bidder_,
            amount: amount96,
            referrer: referrer_,
            status: BidStatus.Submitted
        });

        // Increment the total bid amount
        data.totalBidAmount += amount_;

        // Calculate the new filled capacity including this bid
        // If greater than or equal to the lot capacity, the auction should end
        // If strictly greater than, then this bid is a partial fill
        // If not, then the payout is calculated at the full amount and the auction proceeds
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        uint256 newFilledCapacity = Math.fullMulDiv(data.totalBidAmount, baseScale, data.price);

        // If the new filled capacity is less than the lot capacity, the auction continues
        if (newFilledCapacity < lotCapacity) {
            return bidId;
        }

        // If partial fill, then calculate new payout and refund
        if (newFilledCapacity > lotCapacity) {
            // Store the partial fill
            _lotPartialFill[lotId_] = _calculatePartialFill(
                bidId, lotCapacity, newFilledCapacity, amount96, baseScale, data.price
            );

            // Decrement the total bid amount by the refund
            data.totalBidAmount -= _lotPartialFill[lotId_].refund;

            // Calculate the updated filled capacity
            uint256 filledCapacity = Math.fullMulDiv(data.totalBidAmount, baseScale, data.price);

            // Compare this with minimum filled and update if needed
            // We do this to ensure that slight rounding errors do not cause
            // the auction to not clear when the capacity is actually filled
            // This generally can only happen when the min fill is 100%
            if (filledCapacity < data.minFilled) data.minFilled = filledCapacity;
        }

        // End the auction
        // We don't settle here to preserve callback and storage interactions associated with calling "settle"
        lotData[lotId_].conclusion = uint48(block.timestamp);

        return bidId;
    }

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Marks the bid as claimed
    ///             - Returns the amount to be refunded
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The bid ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is active
    ///             - The bid has not been refunded
    function _refundBid(
        uint96 lotId_,
        uint64 bidId_,
        uint256,
        address
    ) internal override returns (uint256 refund) {
        // Load auction and bid data
        AuctionData storage data = _auctionData[lotId_];
        Bid storage bid = _bids[lotId_][bidId_];

        // Update the bid status
        bid.status = BidStatus.Claimed;

        // Update the total bid amount
        data.totalBidAmount -= bid.amount;

        // Refund is the bid amount
        refund = bid.amount;
    }

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Validates the bid
    ///             - Marks the bid as claimed
    ///             - Calculates the payout and refund
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction has concluded
    ///             - The auction is not settled
    ///
    ///             This function reverts if:
    ///             - The bid ID is invalid
    ///             - The bid has already been claimed
    function _claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    ) internal override returns (BidClaim[] memory bidClaims, bytes memory auctionOutput) {
        uint256 len = bidIds_.length;
        bidClaims = new BidClaim[](len);
        for (uint256 i; i < len; i++) {
            // Validate
            _revertIfBidInvalid(lotId_, bidIds_[i]);
            _revertIfBidClaimed(lotId_, bidIds_[i]);

            // Set the bid status to claimed
            _bids[lotId_][bidIds_[i]].status = BidStatus.Claimed;

            // Load the bid claim data
            bidClaims[i] = _getBidClaim(lotId_, bidIds_[i]);
        }

        return (bidClaims, auctionOutput);
    }

    // ========== SETTLEMENT ========== //

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Sets the auction status to settled
    ///             - Calculates the filled capacity
    ///             - If the filled capacity is less than the minimum filled capacity, the auction does not clear
    ///             - If the filled capacity is greater than or equal to the minimum filled capacity, the auction clears
    ///             - Returns the total in, total out, and whether the auction is finished
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The auction has concluded
    ///             - The auction is not settled
    ///
    ///             This function reverts if:
    ///             - None
    function _settle(
        uint96 lotId_,
        uint256
    )
        internal
        override
        returns (uint256 totalIn_, uint256 totalOut_, bool finished_, bytes memory auctionOutput_)
    {
        // Set the auction status to settled
        _auctionData[lotId_].status = LotStatus.Settled;

        // Calculate the filled capacity
        uint256 filledCapacity = Math.fullMulDiv(
            _auctionData[lotId_].totalBidAmount,
            10 ** lotData[lotId_].baseTokenDecimals,
            _auctionData[lotId_].price
        );

        // If the filled capacity is less than the minimum filled capacity, the auction will not clear
        if (filledCapacity < _auctionData[lotId_].minFilled) {
            // Doesn't clear so we don't set the settlementCleared flag before returning

            // totalIn and totalOut are not set since the auction does not clear
            return (totalIn_, totalOut_, true, auctionOutput_);
        }

        // Otherwise, the auction will clear so we set the settlementCleared flag
        _auctionData[lotId_].settlementCleared = true;

        // Set the output values
        totalIn_ = _auctionData[lotId_].totalBidAmount;
        totalOut_ = filledCapacity;
        finished_ = true;
    }

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Sets the auction status to Settled
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The auction is not settled
    ///             - The dedicated settle period has not passed
    ///
    ///             This function reverts if:
    ///             - None
    function _abort(
        uint96 lotId_
    ) internal override {
        // Set the auction status to settled
        _auctionData[lotId_].status = LotStatus.Settled;

        // Auction doesn't clear so we don't set the settlementCleared flag
    }

    // ========== AUCTION INFORMATION ========== //

    /// @inheritdoc IFixedPriceBatch
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
    ///             - The bid ID is invalid
    function getBid(uint96 lotId_, uint64 bidId_) external view returns (Bid memory bid) {
        _revertIfLotInvalid(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);

        return _bids[lotId_][bidId_];
    }

    /// @inheritdoc IFixedPriceBatch
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
    function getAuctionData(
        uint96 lotId_
    ) external view override returns (AuctionData memory auctionData_) {
        _revertIfLotInvalid(lotId_);

        return _auctionData[lotId_];
    }

    /// @inheritdoc IFixedPriceBatch
    /// @dev        For ease of use, this function determines if a partial fill exists.
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The lot is not settled
    function getPartialFill(
        uint96 lotId_
    ) external view returns (bool hasPartialFill, PartialFill memory partialFill) {
        _revertIfLotInvalid(lotId_);
        _revertIfLotNotSettled(lotId_);

        partialFill = _lotPartialFill[lotId_];
        hasPartialFill = partialFill.bidId != 0;

        return (hasPartialFill, partialFill);
    }

    /// @inheritdoc IBatchAuction
    /// @dev        This function is not implemented in fixed price batch since bid IDs are not stored in an array
    ///             A proxy is using the nextBidId to determine how many bids have been submitted, but this doesn't consider refunds
    function getNumBids(
        uint96
    ) external view override returns (uint256) {}

    /// @inheritdoc IBatchAuction
    /// @dev        This function is not implemented in fixed price batch since bid IDs are not stored in an array
    function getBidIds(uint96, uint256, uint256) external view override returns (uint64[] memory) {}

    /// @inheritdoc IBatchAuction
    /// @dev        This function is not implemented in fixed price batch since bid IDs are not stored in an array
    function getBidIdAtIndex(uint96, uint256) external view override returns (uint64) {}

    /// @inheritdoc IBatchAuction
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
    ///             - The lot is not settled (since there would be no claim)
    ///             - The bid ID is invalid
    function getBidClaim(
        uint96 lotId_,
        uint64 bidId_
    ) external view override returns (BidClaim memory bidClaim) {
        _revertIfLotInvalid(lotId_);
        _revertIfLotNotSettled(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);

        return _getBidClaim(lotId_, bidId_);
    }

    /// @notice Returns the `BidClaim` data for a given lot and bid ID
    /// @dev    This function assumes:
    ///         - The lot ID has been validated
    ///         - The bid ID has been validated
    ///
    /// @param  lotId_          The lot ID
    /// @param  bidId_          The bid ID
    /// @return bidClaim        The `BidClaim` data
    function _getBidClaim(
        uint96 lotId_,
        uint64 bidId_
    ) internal view returns (BidClaim memory bidClaim) {
        // Load bid data
        Bid memory bidData = _bids[lotId_][bidId_];

        // Load the bidder and referrer addresses
        bidClaim.bidder = bidData.bidder;
        bidClaim.referrer = bidData.referrer;

        if (_auctionData[lotId_].settlementCleared) {
            // settlement cleared, so bids are paid out

            if (_lotPartialFill[lotId_].bidId == bidId_) {
                // Partial fill, use the stored data
                bidClaim.paid = bidData.amount;
                bidClaim.payout = _lotPartialFill[lotId_].payout;
                bidClaim.refund = _lotPartialFill[lotId_].refund;
            } else {
                // Bid is paid out at full amount using the fixed price
                bidClaim.paid = bidData.amount;
                bidClaim.payout = Math.fullMulDiv(
                    bidData.amount,
                    10 ** lotData[lotId_].baseTokenDecimals,
                    _auctionData[lotId_].price
                );
                bidClaim.refund = 0;
            }
        } else {
            // settlement not cleared, so bids are refunded
            bidClaim.paid = bidData.amount;
            bidClaim.payout = 0;
            bidClaim.refund = bidData.amount;
        }

        return bidClaim;
    }

    // ========== VALIDATION ========== //

    /// @inheritdoc AuctionModule
    function _revertIfLotActive(
        uint96 lotId_
    ) internal view override {
        if (
            _auctionData[lotId_].status == LotStatus.Created
                && lotData[lotId_].start <= block.timestamp
                && lotData[lotId_].conclusion > block.timestamp
        ) revert Auction_WrongState(lotId_);
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfLotSettled(
        uint96 lotId_
    ) internal view override {
        // Auction must not be settled
        if (_auctionData[lotId_].status == LotStatus.Settled) {
            revert Auction_WrongState(lotId_);
        }
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfLotNotSettled(
        uint96 lotId_
    ) internal view override {
        // Auction must be settled
        if (_auctionData[lotId_].status != LotStatus.Settled) {
            revert Auction_WrongState(lotId_);
        }
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfBidInvalid(uint96 lotId_, uint64 bidId_) internal view override {
        // Bid ID must be less than number of bids for lot
        if (bidId_ >= _auctionData[lotId_].nextBidId) revert Auction_InvalidBidId(lotId_, bidId_);

        // Bid should have a bidder
        if (_bids[lotId_][bidId_].bidder == address(0)) revert Auction_InvalidBidId(lotId_, bidId_);
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) internal view override {
        // Check that sender is the bidder
        if (caller_ != _bids[lotId_][bidId_].bidder) revert NotPermitted(caller_);
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfBidClaimed(uint96 lotId_, uint64 bidId_) internal view override {
        // Bid must not be refunded or claimed (same status)
        if (_bids[lotId_][bidId_].status == BidStatus.Claimed) {
            revert Bid_WrongState(lotId_, bidId_);
        }
    }
}
