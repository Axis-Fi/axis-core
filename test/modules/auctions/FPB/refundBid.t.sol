// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IBatchAuction} from "src/interfaces/modules/IBatchAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbRefundBidTest is FpbTest {
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the bid id is invalid
    //  [X] it reverts
    // [X] when the caller is not the bid owner
    //  [X] it reverts
    // [X] given the bid has been refunded
    //  [X] it reverts
    // [X] given the lot has concluded
    //  [X] it reverts
    // [X] given the lot has been aborted
    //  [X] it reverts
    // [X] given the lot has been settled
    //  [X] it reverts
    // [X] given the lot is in the settlement period
    //  [X] it reverts
    // [X] it returns the refund amount and updates the bid status

    function test_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.refundBid(_lotId, 1, 0, _BIDDER);
    }

    function test_invalidLotId_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _refundBid(1);
    }

    function test_invalidBidId_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_InvalidBidId.selector, _lotId, 1);
        vm.expectRevert(err);

        // Call the function
        _refundBid(1);
    }

    function test_notBidOwner_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IFixedPriceBatch.NotPermitted.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, 1, 0, address(this));
    }

    function test_bidRefunded_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
    {
        // Refund the bid
        _refundBid(1);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Bid_WrongState.selector, _lotId, 1);
        vm.expectRevert(err);

        // Call the function
        _refundBid(1);
    }

    function test_lotConcluded_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _refundBid(1);
    }

    function test_lotAborted_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenLotSettlePeriodHasPassed
        givenLotIsAborted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _refundBid(1);
    }

    function test_lotSettled_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _refundBid(1);
    }

    function test_lotSettlePeriod_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenDuringLotSettlePeriod
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _refundBid(1);
    }

    function test_success()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenBidIsCreated(2e18)
    {
        // Call the function
        uint256 refundAmount = _refundBid(1);

        // Check the refund amount
        assertEq(refundAmount, 1e18, "refundAmount");

        // Check bid state
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Claimed), "status");

        // Check auction data
        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(auctionData.totalBidAmount, 2e18, "totalBidAmount");
    }
}
