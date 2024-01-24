// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {Auction, AuctionModule} from "src/modules/Auction.sol";

contract MockBatchAuctionModule is AuctionModule {
    mapping(uint96 lotId => Bid[]) public bidData;
    mapping(uint96 lotId => mapping(uint256 => bool)) public bidCancelled;
    mapping(uint96 lotId => mapping(uint256 => bool)) public bidRefunded;

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
    ) internal override returns (uint256) {
        // Create a new bid
        Bid memory newBid = Bid({
            bidder: bidder_,
            recipient: recipient_,
            referrer: referrer_,
            amount: amount_,
            minAmountOut: 0,
            auctionParam: auctionData_
        });

        uint256 bidId = bidData[lotId_].length;

        bidData[lotId_].push(newBid);

        return bidId;
    }

    function _cancelBid(
        uint96 lotId_,
        uint256 bidId_,
        address
    ) internal virtual override returns (uint256 refundAmount) {
        // Cancel the bid
        bidCancelled[lotId_][bidId_] = true;

        // Mark the bid as refunded
        bidRefunded[lotId_][bidId_] = true;

        return bidData[lotId_][bidId_].amount;
    }

    function settle(
        uint256 id_,
        Bid[] memory bids_
    ) external virtual returns (uint256[] memory amountsOut) {}

    function payoutFor(
        uint256 id_,
        uint256 amount_
    ) public view virtual override returns (uint256) {}

    function priceFor(
        uint256 id_,
        uint256 payout_
    ) public view virtual override returns (uint256) {}

    function maxPayout(uint256 id_) public view virtual override returns (uint256) {}

    function maxAmountAccepted(uint256 id_) public view virtual override returns (uint256) {}

    function settle(uint96 lotId_)
        external
        virtual
        override
        returns (Bid[] memory winningBids_, bytes memory auctionOutput_)
    {}

    function settle(
        uint96 lotId_,
        Bid[] calldata winningBids_,
        bytes calldata settlementProof_,
        bytes calldata settlementData_
    ) external virtual override returns (uint256[] memory amountsOut, bytes memory auctionOutput) {}

    function getBid(uint96 lotId_, uint256 bidId_) external view returns (Bid memory bid_) {
        bid_ = bidData[lotId_][bidId_];
    }

    function _revertIfBidInvalid(uint96 lotId_, uint256 bidId_) internal view virtual override {
        // Check that the bid exists
        if (bidData[lotId_].length <= bidId_) {
            revert Auction.Auction_InvalidBidId(lotId_, bidId_);
        }
    }

    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint256 bidId_,
        address caller_
    ) internal view virtual override {
        // Check that the bidder is the owner of the bid
        if (bidData[lotId_][bidId_].bidder != caller_) {
            revert Auction.Auction_NotBidder();
        }
    }

    function _revertIfBidCancelled(uint96 lotId_, uint256 bidId_) internal view virtual override {
        // Check that the bid has not been cancelled
        if (bidCancelled[lotId_][bidId_] == true) {
            revert Auction.Auction_InvalidBidId(lotId_, bidId_);
        }
    }
}
