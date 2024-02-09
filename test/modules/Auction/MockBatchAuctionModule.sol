// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {Auction, AuctionModule} from "src/modules/Auction.sol";

contract MockBatchAuctionModule is AuctionModule {
    uint96[] public bidIds;
    uint96 public nextBidId;
    mapping(uint96 lotId => mapping(uint96 => Bid)) public bidData;
    mapping(uint96 lotId => mapping(uint256 => bool)) public bidCancelled;
    mapping(uint96 lotId => mapping(uint256 => bool)) public bidRefunded;

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

    function _auction(uint96, Lot memory, bytes memory) internal virtual override returns (bool) {}

    function _cancelAuction(uint96 id_) internal override {
        //
    }

    function _purchase(
        uint96,
        uint256,
        bytes calldata
    ) internal pure override returns (uint256, bytes memory) {
        revert Auction_NotImplemented();
    }

    function _bid(
        uint96 lotId_,
        address bidder_,
        address recipient_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint96) {
        // Create a new bid
        Bid memory newBid = Bid({
            bidder: bidder_,
            recipient: recipient_,
            referrer: referrer_,
            amount: amount_,
            minAmountOut: 0,
            auctionParam: auctionData_
        });

        uint96 bidId = nextBidId++;

        bidData[lotId_][bidId] = newBid;

        return bidId;
    }

    function _refundBid(
        uint96 lotId_,
        uint96 bidId_,
        address
    ) internal virtual override returns (uint256 refundAmount) {
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

    function settle(
        uint96 lotId_,
        Bid[] memory bids_
    ) external virtual returns (uint256[] memory amountsOut) {}

    function payoutFor(
        uint96 lotId_,
        uint256 amount_
    ) public view virtual override returns (uint256) {}

    function priceFor(
        uint96 lotId_,
        uint256 payout_
    ) public view virtual override returns (uint256) {}

    function maxPayout(uint96 lotId_) public view virtual override returns (uint256) {}

    function maxAmountAccepted(uint96 lotId_) public view virtual override returns (uint256) {}

    function _settle(uint96 lotId_)
        internal
        override
        returns (Bid[] memory winningBids_, bytes memory auctionOutput_)
    {}

    function getBid(uint96 lotId_, uint96 bidId_) external view returns (Bid memory bid_) {
        bid_ = bidData[lotId_][bidId_];
    }

    function _revertIfBidInvalid(uint96 lotId_, uint96 bidId_) internal view virtual override {
        // Check that the bid exists
        if (nextBidId <= bidId_) {
            revert Auction.Auction_InvalidBidId(lotId_, bidId_);
        }
    }

    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint96 bidId_,
        address caller_
    ) internal view virtual override {
        // Check that the bidder is the owner of the bid
        if (bidData[lotId_][bidId_].bidder != caller_) {
            revert Auction.Auction_NotBidder();
        }
    }

    function _revertIfBidRefunded(uint96 lotId_, uint96 bidId_) internal view virtual override {
        // Check that the bid has not been cancelled
        if (bidCancelled[lotId_][bidId_] == true) {
            revert Auction.Auction_InvalidBidId(lotId_, bidId_);
        }
    }

    function _revertIfLotSettled(uint96 lotId_) internal view virtual override {
        // Check that the lot has not been settled
        if (settled[lotId_] == true) {
            revert Auction.Auction_MarketNotActive(lotId_);
        }
    }

    function _revertIfLotNotSettled(uint96 lotId_) internal view virtual override {
        // Check that the lot has been settled
        if (settled[lotId_] == false) {
            revert Auction.Auction_MarketNotActive(lotId_);
        }
    }

    function setIsSettled(uint96 lotId_, bool isSettled_) external {
        settled[lotId_] = isSettled_;
    }
}
