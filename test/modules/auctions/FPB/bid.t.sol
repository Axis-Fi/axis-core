// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbBidTest is FpbTest {
    uint256 internal constant _BID_AMOUNT = 2e18;

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot has not started
    //  [X] it reverts
    // [X] when the lot has concluded
    //  [X] it reverts
    // [X] when the lot has been cancelled
    //  [X] it reverts
    // [X] when the lot has been aborted
    //  [X] it reverts
    // [X] when the lot has been settled
    //  [X] it reverts
    // [X] when the lot is in the settlement period
    //  [X] it reverts
    // [X] when the bid amount is 0
    //  [X] it reverts
    // [X] when the bid amount is greater than uint96 max
    //  [X] it reverts
    // [X] when the auction price is very high or very low
    //  [X] it records the bid accurately
    // [X] when the bid amount reaches capacity
    //  [X] it records the bid and concludes the auction
    // [X] when the bid amount is greater than the remaining capacity
    //  [X] it records the bid, concludes the auction and calculates partial fill
    // [X] it records the bid

    function test_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, abi.encode(""));
    }

    function test_invalidLotId_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT);
    }

    function test_lotNotStarted_reverts() public givenLotIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT);
    }

    function test_lotConcluded_reverts() public givenLotIsCreated givenLotHasConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT);
    }

    function test_lotCancelled_reverts() public givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT);
    }

    function test_lotAborted_reverts()
        public
        givenLotIsCreated
        givenLotSettlePeriodHasPassed
        givenLotIsAborted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT);
    }

    function test_lotSettled_reverts()
        public
        givenLotIsCreated
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT);
    }

    function test_lotInSettlementPeriod_reverts()
        public
        givenLotIsCreated
        givenLotHasConcluded
        givenDuringLotSettlePeriod
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT);
    }

    function test_bidAmountIsZero_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createBid(0);
    }

    function test_bidAmountIsGreaterThanMax_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createBid(uint256(type(uint96).max) + 1);
    }

    function test_bidsReachCapacity() public givenLotIsCreated givenLotHasStarted {
        // Create a bid to fill half capacity (10/2 = 5)
        _createBid(10e18);

        // Create a second bid to fill the remaining capacity exactly
        _createBid(10e18);

        // Assert state
        IAuction.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.capacity, _LOT_CAPACITY, "capacity");
        assertEq(lotData.conclusion, uint48(block.timestamp), "conclusion");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Created), "status");
        assertEq(auctionData.nextBidId, 3, "nextBidId");
        assertEq(auctionData.settlementCleared, false, "settlementCleared"); // Not settled yet
        assertEq(auctionData.totalBidAmount, 20e18, "totalBidAmount");

        // Assert bid one
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(bidData.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidData.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidData.amount, 10e18, "bid one: amount");
        assertEq(
            uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "bid one: status"
        );

        // Assert bid two
        bidData = _module.getBid(_lotId, 2);
        assertEq(bidData.bidder, _BIDDER, "bid two: bidder");
        assertEq(bidData.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidData.amount, 10e18, "bid two: amount");
        assertEq(
            uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "bid two: status"
        );

        // Settle the auction
        _warpAfterSettlePeriod();
        _settleLot();

        // Assert partial fill
        (bool hasPartialFill, IFixedPriceBatch.PartialFill memory partialFill) =
            _module.getPartialFill(_lotId);
        assertEq(hasPartialFill, false, "hasPartialFill");
        assertEq(partialFill.bidId, 0, "partialFill: bidId");
        assertEq(partialFill.refund, 0, "partialFill: refund");
        assertEq(partialFill.payout, 0, "partialFill: payout");
    }

    function test_bidsOverCapacity() public givenLotIsCreated givenLotHasStarted {
        // Create a bid to fill half capacity (10/2 = 5)
        _createBid(10e18);

        // Create a second bid to fill the over the remaining capacity (12/2 = 6)
        _createBid(12e18);

        // Assert state
        IAuction.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.capacity, _LOT_CAPACITY, "capacity");
        assertEq(lotData.conclusion, uint48(block.timestamp), "conclusion");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Created), "status");
        assertEq(auctionData.nextBidId, 3, "nextBidId");
        assertEq(auctionData.settlementCleared, false, "settlementCleared"); // Not settled yet
        assertEq(auctionData.totalBidAmount, 20e18, "totalBidAmount"); // Excludes refund

        // Assert bid one
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(bidData.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidData.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidData.amount, 10e18, "bid one: amount");
        assertEq(
            uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "bid one: status"
        );

        // Assert bid two
        bidData = _module.getBid(_lotId, 2);
        assertEq(bidData.bidder, _BIDDER, "bid two: bidder");
        assertEq(bidData.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidData.amount, 12e18, "bid two: amount");
        assertEq(
            uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "bid two: status"
        );

        // Settle the auction
        _warpAfterSettlePeriod();
        _settleLot();

        // Assert partial fill
        (bool hasPartialFill, IFixedPriceBatch.PartialFill memory partialFill) =
            _module.getPartialFill(_lotId);
        assertEq(hasPartialFill, true, "hasPartialFill");
        assertEq(partialFill.bidId, 2, "partialFill: bidId");
        assertEq(partialFill.refund, 2e18, "partialFill: refund");
        assertEq(partialFill.payout, 5e18, "partialFill: payout");
    }

    function test_singleBidOverCapacity() public givenLotIsCreated givenLotHasStarted {
        // Create a bid to that exceeds capacity (22/2 = 11)
        _createBid(22e18);

        // Assert state
        IAuction.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.capacity, _LOT_CAPACITY, "capacity");
        assertEq(lotData.conclusion, uint48(block.timestamp), "conclusion");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Created), "status");
        assertEq(auctionData.nextBidId, 2, "nextBidId");
        assertEq(auctionData.settlementCleared, false, "settlementCleared"); // Not settled yet
        assertEq(auctionData.totalBidAmount, 20e18, "totalBidAmount"); // Excludes refund

        // Assert bid one
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(bidData.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidData.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidData.amount, 22e18, "bid one: amount");
        assertEq(
            uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "bid one: status"
        );

        // Settle the auction
        _warpAfterSettlePeriod();
        _settleLot();

        // Assert partial fill
        (bool hasPartialFill, IFixedPriceBatch.PartialFill memory partialFill) =
            _module.getPartialFill(_lotId);
        assertEq(hasPartialFill, true, "hasPartialFill");
        assertEq(partialFill.bidId, 1, "partialFill: bidId");
        assertEq(partialFill.refund, 2e18, "partialFill: refund");
        assertEq(partialFill.payout, 10e18, "partialFill: payout");
    }

    function test_bidsUnderCapacity() public givenLotIsCreated givenLotHasStarted {
        // Create a bid to fill half capacity (10/2 = 5)
        _createBid(10e18);

        // Assert state
        IAuction.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.capacity, _LOT_CAPACITY, "capacity");
        assertEq(lotData.conclusion, _start + _DURATION, "conclusion");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Created), "status");
        assertEq(auctionData.nextBidId, 2, "nextBidId");
        assertEq(auctionData.settlementCleared, false, "settlementCleared"); // Not settled yet
        assertEq(auctionData.totalBidAmount, 10e18, "totalBidAmount");

        // Assert bid one
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(bidData.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidData.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidData.amount, 10e18, "bid one: amount");
        assertEq(
            uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "bid one: status"
        );
    }

    function test_partialFill_auctionPriceFuzz(uint256 price_) public {
        uint256 price = bound(price_, 1, type(uint256).max);
        _setPrice(price);

        // Create the auction
        _createAuctionLot();

        // Warp to start
        _startLot();

        // Calculate a bid amount that would result in a partial fill
        uint256 bidAmount = 11e18 * price / (10 ** _baseTokenDecimals);
        uint256 maxBidAmount = 10e18 * price / (10 ** _baseTokenDecimals);

        // Create a bid
        _createBid(bidAmount);

        // Settle the auction
        _warpAfterSettlePeriod();
        _settleLot();

        // Assert partial fill
        (bool hasPartialFill, IFixedPriceBatch.PartialFill memory partialFill) =
            _module.getPartialFill(_lotId);
        assertEq(hasPartialFill, true, "hasPartialFill");
        assertEq(partialFill.bidId, 1, "partialFill: bidId");
        assertEq(partialFill.refund, bidAmount - maxBidAmount, "partialFill: refund");
        assertEq(partialFill.payout, 10e18, "partialFill: payout");
    }
}
