// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "../../../../src/modules/Modules.sol";
import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {IBatchAuction} from "../../../../src/interfaces/modules/IBatchAuction.sol";
import {IFixedPriceBatch} from "../../../../src/interfaces/modules/auctions/IFixedPriceBatch.sol";

import {FpbTest} from "./FPBTest.sol";

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

    // bug encountered in prod
    function test_partialFill_roundingError()
        public
        givenPrice(15_120_710_000_000)
        givenMinFillPercent(100e2)
        givenLotCapacity(1_000_000e18)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Auction parameters
        // Capacity: 1,000,000 FLAPPY
        // Price: 0.00001512071 ETH/FLAPPY
        // Expected Proceeds: 15.12071 ETH

        // Observed results with complete fill:
        // Tokens Sold: 999999.999999999999933865 FLAPPY
        // Proceeds: 15.120709999999999999 ETH
        // The reason these values are lower is that we introduced rounding behavior
        // so that the refund on a partial fill would be slightly larger to not oversell
        // the auction. If oversold, settle bricks so we round up the refund to prevent this.

        // However, the partial fill payout ended up being too high and caused an error
        // when that user went to claim their bid. This is because a refund of 0.000000000000066135 FLAPPY
        // was sent from the auction house back to the callback on settlement since the sold value was
        // less than the capacity. Thus, the auction house did not have enough capacity to pay out all
        // of the successful bids at that point (it was 0.000000000000066105 FLAPPY short).

        // To recreate this, we submit two bids. The first is for all the capacity that was expended before
        // the partial bid was placed, and the second bid is the same as the observed partial bid.

        // The partial bid was for 0.3 ETH and they received:
        // Filled: 0.083710000000000000 ETH
        // Refund: 0.216290000000000001 ETH
        // Payout: 5,536.11569827078225824 FLAPPY

        // The first bid should then be for 15.12071 - 0.08371 ETH = 15.037 ETH
        vm.prank(address(_auctionHouse));
        uint64 id1 =
            _module.bid(_lotId, _BIDDER, _REFERRER, 15_037_000_000_000_000_000, abi.encode(""));

        // The second bid should be for 0.3 ETH
        vm.prank(address(_auctionHouse));
        uint64 id2 = _module.bid(_lotId, _BIDDER, _REFERRER, 3e17, abi.encode(""));

        // Settle the auction
        vm.prank(address(_auctionHouse));
        (uint256 totalIn, uint256 totalOut,, bool finished,) = _module.settle(_lotId, 2);

        // Check that the auction is settled and the results are what we expect
        assertEq(totalIn, 15_120_709_999_999_999_999);
        assertEq(totalOut, 999_999_999_999_999_999_933_865);
        assertTrue(finished);

        // Assert that the total out is equal to the capacity minus the refund sent to the seller
        assertEq(totalOut, 1_000_000e18 - 66_135);

        // Validate that the bid claims add up to less than or equal the total out
        IBatchAuction.BidClaim memory bidClaim1 = _module.getBidClaim(_lotId, id1);
        IBatchAuction.BidClaim memory bidClaim2 = _module.getBidClaim(_lotId, id2);

        assertLe(bidClaim1.payout + bidClaim2.payout, totalOut);
    }
}
