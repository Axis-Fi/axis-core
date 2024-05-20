// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

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
}
