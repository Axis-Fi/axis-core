// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {Auction, AuctionModule} from "src/modules/Auction.sol";

contract MockBatchAuctionModule is AuctionModule {
    enum BidStatus {
        Submitted,
        Decrypted,
        // Bid status will also be set to claimed if the bid is cancelled/refunded
        Claimed
    }

    /// @notice        Core data for a bid
    ///
    /// @param         status              The status of the bid
    /// @param         bidder              The address of the bidder
    /// @param         amount              The amount of the bid
    /// @param         minAmountOut        The minimum amount out (not set until the bid is decrypted)
    /// @param         referrer            The address of the referrer
    struct Bid {
        address bidder; // 20 +
        uint96 amount; // 12 = 32 - end of slot 1
        uint96 minAmountOut; // 12 +
        address referrer; // 20 = 32 - end of slot 2
        BidStatus status; // 1 - slot 3
    }

    uint64[] public bidIds;
    uint64 public nextBidId;
    mapping(uint96 lotId => mapping(uint64 => Bid)) public bidData;
    mapping(uint96 lotId => mapping(uint64 => bool)) public bidCancelled;
    mapping(uint96 lotId => mapping(uint64 => bool)) public bidRefunded;

    mapping(uint96 lotId => Settlement) public lotSettlements;

    mapping(uint96 lotId => Auction.Status) public lotStatus;

    mapping(uint96 => bool) public settled;

    constructor(address _owner) AuctionModule(_owner) {
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("BATCH"), 1);
    }

    function TYPE() public pure virtual override returns (Type) {
        return Type.Auction;
    }

    /// @inheritdoc Auction
    function auctionType() external pure override returns (AuctionType) {
        return AuctionType.Batch;
    }

    function _auction(uint96, Lot memory, bytes memory) internal virtual override {}

    function _cancelAuction(uint96 id_) internal override {
        //
    }

    function _purchase(
        uint96,
        uint96,
        bytes calldata
    ) internal pure override returns (uint96, bytes memory) {
        revert Auction_NotImplemented();
    }

    function _bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint96 amount_,
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
        address
    ) internal virtual override returns (uint96 refundAmount) {
        // Cancel the bid
        bidCancelled[lotId_][bidId_] = true;

        // Mark the bid as refunded
        bidRefunded[lotId_][bidId_] = true;

        // Remove from bid id array
        uint256 len = bidIds.length;
        for (uint256 i = 0; i < len; i++) {
            if (bidIds[i] == bidId_) {
                bidIds[i] = bidIds[len - 1];
                bidIds.pop();
                break;
            }
        }

        return bidData[lotId_][bidId_].amount;
    }

    function _claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    ) internal virtual override returns (BidClaim[] memory bidClaims, bytes memory auctionOutput) {}

    function setLotSettlement(uint96 lotId_, Settlement calldata settlement_) external {
        lotSettlements[lotId_] = settlement_;

        // Also update sold and purchased
        Lot storage lot = lotData[lotId_];
        lot.purchased = uint96(settlement_.totalIn);
        lot.sold = uint96(settlement_.totalOut);
        lot.partialPayout = uint96(settlement_.pfPayout);
    }

    function _settle(uint96 lotId_) internal override returns (Settlement memory, bytes memory) {
        // Update status
        lotStatus[lotId_] = Auction.Status.Settled;

        return (lotSettlements[lotId_], "");
    }

    function _claimProceeds(uint96 lotId_) internal override returns (uint96, uint96, uint96) {
        // Update status
        lotStatus[lotId_] = Auction.Status.Claimed;

        Lot storage lot = lotData[lotId_];
        return (lot.purchased, lot.sold, lot.partialPayout);
    }

    function getBid(uint96 lotId_, uint64 bidId_) external view returns (Bid memory bid_) {
        bid_ = bidData[lotId_][bidId_];
    }

    function _revertIfBidInvalid(uint96 lotId_, uint64 bidId_) internal view virtual override {
        // Check that the bid exists
        if (nextBidId <= bidId_) {
            revert Auction.Auction_InvalidBidId(lotId_, bidId_);
        }
    }

    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) internal view virtual override {
        // Check that the bidder is the owner of the bid
        if (bidData[lotId_][bidId_].bidder != caller_) {
            revert Auction.Auction_NotBidder();
        }
    }

    function _revertIfBidClaimed(uint96 lotId_, uint64 bidId_) internal view virtual override {
        // Check that the bid has not been cancelled
        if (bidCancelled[lotId_][bidId_] == true) {
            revert Auction.Auction_InvalidBidId(lotId_, bidId_);
        }
    }

    function _revertIfLotSettled(uint96 lotId_) internal view virtual override {
        // Check that the lot has not been settled
        if (lotStatus[lotId_] == Auction.Status.Settled) {
            revert Auction.Auction_MarketNotActive(lotId_);
        }
    }

    function _revertIfLotNotSettled(uint96 lotId_) internal view virtual override {
        // Check that the lot has been settled
        if (lotStatus[lotId_] != Auction.Status.Settled) {
            revert Auction.Auction_InvalidParams();
        }
    }

    function _revertIfLotProceedsClaimed(uint96 lotId_) internal view virtual override {
        // Check that the lot has not been claimed
        if (lotStatus[lotId_] == Auction.Status.Claimed) {
            revert Auction.Auction_InvalidParams();
        }
    }
}
