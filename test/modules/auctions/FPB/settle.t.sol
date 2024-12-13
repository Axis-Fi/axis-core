// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "../../../../src/modules/Modules.sol";
import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "../../../../src/interfaces/modules/auctions/IFixedPriceBatch.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

import {FpbTest} from "./FPBTest.sol";

contract FpbSettleTest is FpbTest {
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot has not started
    //  [X] it reverts
    // [X] when the lot has not concluded
    //  [X] it reverts
    // [X] when the lot has been cancelled
    //  [X] it reverts
    // [X] when the lot has been aborted
    //  [X] it reverts
    // [X] when the lot has been settled
    //  [X] it reverts
    // [X] when the lot is in the settlement period
    //  [X] it settles
    // [X] when the filled capacity is below the minimum
    //  [X] it marks the settlement as not cleared and updates the status
    // [X] it marks the settlement as cleared, updates the status and returns the total in and out

    function test_notParent_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.settle(_lotId, 100_000);
    }

    function test_invalidLotId_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _settleLot();
    }

    function test_lotHasNotStarted_reverts() public givenLotIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _settleLot();
    }

    function test_lotHasNotConcluded_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _settleLot();
    }

    function test_lotHasBeenCancelled_reverts() public givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _settleLot();
    }

    function test_lotHasBeenAborted_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenLotSettlePeriodHasPassed
        givenLotIsAborted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _settleLot();
    }

    function test_lotHasBeenSettled_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _settleLot();
    }

    function test_duringSettlementPeriod()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(10e18)
        givenLotHasConcluded
    {
        // Call the function
        _settleLot();

        // Assert state
        IFixedPriceBatch.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.conclusion, _start + _DURATION, "conclusion");
        assertEq(lotData.capacity, _LOT_CAPACITY, "capacity");
        assertEq(lotData.purchased, 10e18, "purchased");
        assertEq(lotData.sold, 5e18, "sold");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Settled), "status");
        assertEq(auctionData.settlementCleared, true, "settlementCleared");
        assertEq(auctionData.totalBidAmount, 10e18, "totalBidAmount");
    }

    function test_settlementClears()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(10e18)
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
    {
        // Call the function
        _settleLot();

        // Assert state
        IFixedPriceBatch.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.conclusion, _start + _DURATION, "conclusion");
        assertEq(lotData.capacity, _LOT_CAPACITY, "capacity");
        assertEq(lotData.purchased, 10e18, "purchased");
        assertEq(lotData.sold, 5e18, "sold");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Settled), "status");
        assertEq(auctionData.settlementCleared, true, "settlementCleared");
        assertEq(auctionData.totalBidAmount, 10e18, "totalBidAmount");
    }

    function test_belowMinFillPercent()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(6e18)
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
    {
        // Call the function
        _settleLot();

        // Assert state
        IFixedPriceBatch.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.conclusion, _start + _DURATION, "conclusion");
        assertEq(lotData.capacity, _LOT_CAPACITY, "capacity");
        assertEq(lotData.purchased, 0, "purchased");
        assertEq(lotData.sold, 0, "sold");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Settled), "status");
        assertEq(auctionData.settlementCleared, false, "settlementCleared");
        assertEq(auctionData.totalBidAmount, 6e18, "totalBidAmount");
    }

    // Added per ethersky's review (issue 201) to avoid a rounding issue which prevents settlement
    function test_settle_doesNotBrick()
        public
        givenPrice(2e18)
        givenMinFillPercent(100e2)
        givenLotCapacity(10e18)
        givenLotIsCreated
        givenLotHasStarted
    {
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, 2e19 - 1, abi.encode(""));

        IFixedPriceBatch.AuctionData memory auctionDataBefore = _module.getAuctionData(_lotId);
        IAuction.Lot memory lotBefore = _module.getLot(_lotId);
        console2.log("totalBidAmount before    ==>  ", auctionDataBefore.totalBidAmount);
        console2.log("conclusion before        ==>  ", lotBefore.conclusion);

        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, 1e18 + 1, abi.encode(""));

        IFixedPriceBatch.AuctionData memory auctionDataAfter = _module.getAuctionData(_lotId);
        IAuction.Lot memory lotAfter = _module.getLot(_lotId);

        console2.log("totalBidAmount after     ==>  ", auctionDataAfter.totalBidAmount);
        console2.log("conclusion after         ==>  ", lotAfter.conclusion);
        assertLt(lotAfter.conclusion, lotBefore.conclusion);

        vm.prank(address(_auctionHouse));
        _module.settle(_lotId, 100_000);

        IFixedPriceBatch.AuctionData memory auctionDataFinal = _module.getAuctionData(_lotId);

        console2.log("settlementCleared final  ==>  ", auctionDataFinal.settlementCleared);
        assert(auctionDataFinal.settlementCleared);
    }

    // Added due to scenario encountered in the wild
    function test_settle_lowPrice_doesNotBrick()
        public
        givenPrice(15_120_710_000_000)
        givenMinFillPercent(100e2)
        givenLotCapacity(1_000_000e18)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Overbid
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, 15_120_710_000_000_000_001, abi.encode(""));

        // Settle the auction
        vm.prank(address(_auctionHouse));
        (uint256 totalIn, uint256 totalOut, uint256 capacity,,) = _module.settle(_lotId, 0);

        // Ensure the total out is not more than the capacity
        console2.log("totalOut  ==>  ", totalOut);
        console2.log("capacity  ==>  ", capacity);
        console2.log("totalIn   ==>  ", totalIn);

        assertLe(totalOut, capacity);
        assertLe(totalIn, 15_120_710_000_000_000_000);
    }

    function testFuzz_settle_partialFill_doesNotBrick(
        uint96 price_,
        uint96 capacity_,
        uint96 amount_
    ) public givenMinFillPercent(100e2) {
        // Don't test really low values
        // We limit the inputs to uint96 to avoid very high values
        vm.assume(price_ > 1e6);
        vm.assume(capacity_ > 1e6);
        vm.assume(amount_ > uint256(price_) * uint256(capacity_) / 1e18);

        _setPrice(uint256(price_));
        _setCapacity(uint256(capacity_));
        _createAuctionLot();
        _startLot();

        // Overbid
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, amount_, abi.encode(""));

        // Settle the auction
        vm.prank(address(_auctionHouse));
        (, uint256 totalOut, uint256 capacity,,) = _module.settle(_lotId, 0);

        // Ensure the total out is not more than the capacity
        console2.log("totalOut  ==>  ", totalOut);
        console2.log("capacity  ==>  ", capacity);

        assertLe(totalOut, capacity);
    }
}
