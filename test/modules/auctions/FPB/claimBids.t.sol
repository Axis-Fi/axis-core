// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IBatchAuction} from "src/interfaces/modules/IBatchAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbClaimBidsTest is FpbTest {
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when any bid id is invalid
    //  [X] it reverts
    // [X] given the lot has not concluded
    //  [X] it reverts
    // [X] given any bid has been claimed
    //  [X] it reverts
    // [X] given it is during the settlement period
    //  [X] it reverts
    // [X] given the lot is not settled
    //  [X] it reverts
    // [X] given the auction was aborted
    //  [X] it returns the refund amount and updates the bid status
    // [X] given the settlement cleared
    //  [X] given the bid was a partial fill
    //   [X] it returns the payout and refund amounts and updates the bid status
    //  [X] it returns the refund amount and updates the bid status
    // [X] it returns the refund amount and updates the bid status
    // [X] it returns the bid claims for multiple bids

    function test_notParent_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.claimBids(_lotId, new uint64[](1));
    }

    function test_invalidLotId_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _claimBid(1);
    }

    function test_invalidBidId_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_InvalidBidId.selector, _lotId, 1);
        vm.expectRevert(err);

        // Call the function
        _claimBid(1);
    }

    function test_lotNotConcluded_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _claimBid(1);
    }

    function test_bidClaimed_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Claim the bid
        _claimBid(1);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Bid_WrongState.selector, _lotId, 1);
        vm.expectRevert(err);

        // Call the function
        _claimBid(1);
    }

    function test_duringSettlementPeriod_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _claimBid(1);
    }

    function test_lotNotSettled_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _claimBid(1);
    }

    function test_lotAborted()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18)
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
        givenLotIsAborted
    {
        // Call the function
        (IBatchAuction.BidClaim[] memory bidClaims,) = _claimBid(1);

        // Check values
        assertEq(bidClaims.length, 1, "bidClaims length");

        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.paid, 1e18, "paid");
        assertEq(bidClaim.refund, 1e18, "refund");
        assertEq(bidClaim.payout, 0, "payout");

        // Assert bid state
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Claimed), "status");
    }

    function test_lotSettlementClears()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(6e18)
        givenBidIsCreated(6e18)
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Claim the first bid
        (IBatchAuction.BidClaim[] memory bidClaims,) = _claimBid(1);

        // Check values
        assertEq(bidClaims.length, 1, "bidClaims length");

        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.paid, 6e18, "paid");
        assertEq(bidClaim.refund, 0, "refund");
        assertEq(bidClaim.payout, 3e18, "payout"); // 6/2

        // Check the bid state
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Claimed), "status");

        IFixedPriceBatch.Bid memory bidDataTwo = _module.getBid(_lotId, 2);
        assertEq(uint8(bidDataTwo.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "status");
    }

    function test_lotSettlementDoesNotClear()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18)
        givenBidIsCreated(2e18)
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Claim the first bid
        (IBatchAuction.BidClaim[] memory bidClaims,) = _claimBid(1);

        // Check values
        assertEq(bidClaims.length, 1, "bidClaims length");

        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.paid, 2e18, "paid");
        assertEq(bidClaim.refund, 2e18, "refund");
        assertEq(bidClaim.payout, 0, "payout");

        // Check the bid state
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Claimed), "status");

        IFixedPriceBatch.Bid memory bidDataTwo = _module.getBid(_lotId, 2);
        assertEq(uint8(bidDataTwo.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "status");
    }

    function test_lotSettlementClears_partialFill()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(10e18)
        givenBidIsCreated(12e18)
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Claim the second bid (partial fill)
        (IBatchAuction.BidClaim[] memory bidClaims,) = _claimBid(2);

        // Check values
        assertEq(bidClaims.length, 1, "bidClaims length");

        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.paid, 12e18, "paid");
        assertEq(bidClaim.refund, 2e18, "refund");
        assertEq(bidClaim.payout, 5e18, "payout"); // 10/2

        // Check the bid state
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Submitted), "status");

        IFixedPriceBatch.Bid memory bidDataTwo = _module.getBid(_lotId, 2);
        assertEq(uint8(bidDataTwo.status), uint8(IFixedPriceBatch.BidStatus.Claimed), "status");
    }

    function test_multipleBids()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(6e18)
        givenBidIsCreated(8e18)
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Claim both bids
        uint64[] memory bidIds = new uint64[](2);
        bidIds[0] = 1;
        bidIds[1] = 2;

        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check values
        assertEq(bidClaims.length, 2, "bidClaims length");

        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.paid, 6e18, "paid");
        assertEq(bidClaim.refund, 0, "refund");
        assertEq(bidClaim.payout, 3e18, "payout"); // 6/2

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.paid, 8e18, "paid");
        assertEq(bidClaimTwo.refund, 0, "refund");
        assertEq(bidClaimTwo.payout, 4e18, "payout"); // 8/2

        // Check the bid state
        IFixedPriceBatch.Bid memory bidData = _module.getBid(_lotId, 1);
        assertEq(uint8(bidData.status), uint8(IFixedPriceBatch.BidStatus.Claimed), "status");

        IFixedPriceBatch.Bid memory bidDataTwo = _module.getBid(_lotId, 2);
        assertEq(uint8(bidDataTwo.status), uint8(IFixedPriceBatch.BidStatus.Claimed), "status");
    }
}
