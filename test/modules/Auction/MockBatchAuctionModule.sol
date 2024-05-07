// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";
import {BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";
import {IBatchAuction} from "src/interfaces/IBatchAuction.sol";

// Auctions
import {IAuction} from "src/interfaces/IAuction.sol";
import {AuctionModule} from "src/modules/Auction.sol";

contract MockBatchAuctionModule is BatchAuctionModule {
    enum LotStatus {
        Created,
        Settled
    }

    enum BidStatus {
        Submitted,
        // Bid status will also be set to claimed if the bid is cancelled/refunded
        Claimed
    }

    /// @notice        Core data for a bid
    /// @dev           Generic batch auctions do not have to use the uint96 size like EMPA
    ///
    /// @param         status              The status of the bid
    /// @param         bidder              The address of the bidder
    /// @param         amount              The amount of the bid
    /// @param         minAmountOut        The minimum amount out (not set until the bid is decrypted)
    /// @param         referrer            The address of the referrer
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 minAmountOut;
        address referrer;
        BidStatus status; // 1 - slot 3
    }

    uint64[] public bidIds;
    uint64 public nextBidId;
    mapping(uint96 lotId => mapping(uint64 => Bid)) public bidData;
    mapping(uint96 lotId => mapping(uint64 => bool)) public bidCancelled;
    mapping(uint96 lotId => mapping(uint64 => bool)) public bidRefunded;
    mapping(uint96 lotId => mapping(uint64 => BidClaim)) public bidClaims;

    mapping(uint96 lotId => LotStatus) public lotStatus;

    mapping(uint96 => bool) public settlementFinished;

    constructor(address _owner) AuctionModule(_owner) {
        minAuctionDuration = 1 days;
        dedicatedSettlePeriod = 1 days;
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("BATCH"), 1);
    }

    function _auction(uint96, Lot memory, bytes memory) internal virtual override {}

    function _cancelAuction(uint96 id_) internal override {}

    function _bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint256 amount_,
        bytes calldata
    ) internal override returns (uint64) {
        // Create a new bid
        Bid memory newBid = Bid({
            bidder: bidder_,
            referrer: referrer_,
            amount: amount_,
            minAmountOut: 0,
            status: BidStatus.Submitted
        });

        uint64 bidId = nextBidId++;

        bidData[lotId_][bidId] = newBid;

        return bidId;
    }

    function _refundBid(
        uint96 lotId_,
        uint64 bidId_,
        uint256 index_,
        address
    ) internal virtual override returns (uint256 refundAmount) {
        // Cancel the bid
        bidCancelled[lotId_][bidId_] = true;

        // Mark the bid as refunded
        bidRefunded[lotId_][bidId_] = true;

        // Remove from bid id array
        uint256 len = bidIds.length;
        if (len != 0 && index_ < len) {
            bidIds[index_] = bidIds[len - 1];
            bidIds.pop();
        }

        return bidData[lotId_][bidId_].amount;
    }

    function addBidClaim(
        uint96 lotId_,
        uint64 bidId_,
        address bidder_,
        address referrer_,
        uint256 paid_,
        uint256 payout_,
        uint256 refund_
    ) public {
        BidClaim storage claim = bidClaims[lotId_][bidId_];
        claim.bidder = bidder_;
        claim.referrer = referrer_;
        claim.paid = paid_;
        claim.payout = payout_;
        claim.refund = refund_;
    }

    function _claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    )
        internal
        virtual
        override
        returns (BidClaim[] memory bidClaims_, bytes memory auctionOutput_)
    {
        uint256 len = bidIds_.length;
        bidClaims_ = new BidClaim[](len);

        for (uint256 i = 0; i < len; i++) {
            uint64 bidId = bidIds_[i];
            bidClaims_[i] = bidClaims[lotId_][bidId];
        }

        return (bidClaims_, "");
    }

    function setLotSettlement(
        uint96 lotId_,
        uint256 totalIn_,
        uint256 totalOut_,
        bool finished_
    ) external {
        // Also update sold and purchased
        Lot storage lot = lotData[lotId_];
        lot.purchased = totalIn_;
        lot.sold = totalOut_;

        settlementFinished[lotId_] = finished_;
    }

    /// @inheritdoc BatchAuctionModule
    function _settle(
        uint96 lotId_,
        uint256
    )
        internal
        override
        returns (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput)
    {
        // Update status
        if (settlementFinished[lotId_] == true) {
            lotStatus[lotId_] = LotStatus.Settled;
        }

        return (lotData[lotId_].purchased, lotData[lotId_].sold, settlementFinished[lotId_], "");
    }

    function _abort(uint96 lotId_) internal override {
        // Update status
        lotStatus[lotId_] = LotStatus.Settled;
    }

    function getBid(uint96 lotId_, uint64 bidId_) external view returns (Bid memory bid_) {
        bid_ = bidData[lotId_][bidId_];
    }

    function _revertIfBidInvalid(uint96 lotId_, uint64 bidId_) internal view virtual override {
        // Check that the bid exists
        if (nextBidId <= bidId_) {
            revert IBatchAuction.Auction_InvalidBidId(lotId_, bidId_);
        }
    }

    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) internal view virtual override {
        // Check that the bidder is the owner of the bid
        if (bidData[lotId_][bidId_].bidder != caller_) {
            revert IBatchAuction.Auction_NotBidder();
        }
    }

    function _revertIfBidClaimed(uint96 lotId_, uint64 bidId_) internal view virtual override {
        // Check that the bid has not been cancelled
        if (bidCancelled[lotId_][bidId_] == true) {
            revert IBatchAuction.Auction_InvalidBidId(lotId_, bidId_);
        }
    }

    function _revertIfLotSettled(uint96 lotId_) internal view virtual override {
        // Check that the lot has not been settled
        if (lotStatus[lotId_] == LotStatus.Settled) {
            revert IAuction.Auction_LotNotActive(lotId_);
        }
    }

    function _revertIfLotNotSettled(uint96 lotId_) internal view virtual override {
        // Check that the lot has been settled
        if (lotStatus[lotId_] != LotStatus.Settled) {
            revert IAuction.Auction_InvalidParams();
        }
    }

    function getNumBids(uint96) external view override returns (uint256) {
        return bidIds.length;
    }

    function getBidIds(
        uint96,
        uint256 start_,
        uint256 count_
    ) external view override returns (uint64[] memory) {
        uint256 len = bidIds.length;
        uint256 end = start_ + count_ > len ? len : start_ + count_;

        uint64[] memory ids = new uint64[](end - start_);
        for (uint256 i = start_; i < end; i++) {
            ids[i - start_] = bidIds[i];
        }

        return ids;
    }

    function getBidClaim(
        uint96 lotId_,
        uint64 bidId_
    ) external view override returns (BidClaim memory claim_) {
        claim_ = bidClaims[lotId_][bidId_];
    }
}
