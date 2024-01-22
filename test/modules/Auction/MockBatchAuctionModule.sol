// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {Auction, AuctionModule} from "src/modules/Auction.sol";

contract MockBatchAuctionModule is AuctionModule {
    mapping(uint96 lotId => Bid[]) public bidData;

    constructor(address _owner) AuctionModule(_owner) {
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("BATCH"), 1);
    }

    function TYPE() public pure virtual override returns (Type) {
        return Type.Auction;
    }

    function _auction(uint96, Lot memory, bytes memory) internal virtual override {}

    function _cancelAuction(uint96 id_) internal override {
        //
    }

    function purchase(
        uint96,
        uint256,
        bytes calldata
    ) external virtual override returns (uint256, bytes memory) {
        revert Auction_NotImplemented();
    }

    function bid(
        uint96 lotId_,
        address bidder_,
        address recipient_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_,
        bytes calldata approval_
    ) external virtual override returns (uint256) {
        // Valid lot
        if (lotData[lotId_].start == 0) {
            revert Auction.Auction_InvalidLotId(lotId_);
        }

        // If auction is cancelled
        if (isLive(lotId_) == false) {
            revert Auction.Auction_MarketNotActive(lotId_);
        }

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

    function cancelBid(uint96 lotId_, uint256 bidId_, address bidder_) external virtual override {}

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

    function settle(
        uint96 lotId_,
        Bid[] calldata winningBids_,
        bytes calldata settlementProof_,
        bytes calldata settlementData_
    ) external virtual override returns (uint256[] memory amountsOut, bytes memory auctionOutput) {}

    function getBid(uint96 lotId_, uint256 bidId_) external view returns (Bid memory bid_) {
        bid_ = bidData[lotId_][bidId_];
    }

    function claimRefund(
        uint96 lotId_,
        uint256 bidId_,
        address bidder_
    ) external virtual override {}
}
