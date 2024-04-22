// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console2} from "forge-std/console2.sol";

import {Module} from "src/modules/Modules.sol";
import {IAuctionModule} from "src/interfaces/IAuctionModule.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/EMP.sol";
import {BatchAuction} from "src/modules/auctions/BatchAuctionModule.sol";

import {EmpTest} from "test/modules/auctions/EMP/EMPTest.sol";

contract EmpaModuleRefundBidTest is EmpTest {
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the bid id is invalid
    //  [X] it reverts
    // [X] when the bidder is not the the bid owner
    //  [X] it reverts
    // [X] given the bid has already been refunded
    //  [X] it reverts
    // [X] given the lot has been cancelled
    //  [X] it reverts
    // [X] given the lot is concluded (and not decrypted)
    //  [X] given it is within the settle period
    //   [X] it reverts
    //  [X] it refunds the bid amount and updates the bid status
    // [X] given the lot is decrypted
    //  [X] it reverts
    // [X] given the lot is settled
    //  [X] it reverts
    // [X] given the lot proceeds have been claimed
    //  [X] it reverts
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the bid id does not match the id at the index
    //  [X] it reverts
    // [X] when the index is out of bounds
    //  [X] it reverts
    // [X] it refunds the bid amount and updates the bid status
    // [X] it refunds the exact bid amount
    // [X] it works for multiple bids

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionModule.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_invalidBidId_reverts() external givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BatchAuction.Auction_InvalidBidId.selector, _lotId, _bidId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_bidderIsNotBidOwner_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPrice.NotPermitted.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, address(this));
    }

    function test_bidAlreadyRefunded_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsRefunded(_bidId)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPrice.Bid_WrongState.selector, _lotId, _bidId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_lotSettlePeriodHasPassed()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotSettlePeriodHasPassed
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, 0, _BIDDER);

        // Assert the bid status
        EncryptedMarginalPrice.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(
            uint8(bidData.status), uint8(EncryptedMarginalPrice.BidStatus.Claimed), "bid status"
        );

        // Assert the refund amount
        assertEq(refundAmount, 2e18, "refund amount");
    }

    function test_lotIsConcluded_reverts(uint48 elapsed_)
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotHasConcluded
    {
        // Set the elapsed time
        uint48 elapsed =
            uint48(bound(elapsed_, _start + _DURATION, _start + _DURATION + 6 hours - 1));
        vm.warp(elapsed);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_lotIsCancelled_reverts() external givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionModule.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_lotIsDecrypted_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_lotIsSettled_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_lotProceedsClaimed_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
        givenLotProceedsAreClaimed
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_callerIsNotParent_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(this));
        _module.refundBid(_lotId, _bidId, 0, _BIDDER);
    }

    function test_bidNotAtIndex_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(3e18, 1e18)
        givenBidIsCreated(4e18, 1e18)
    {
        // Give a mismatched bid ID and index
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionModule.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, 3, 0, _BIDDER);
    }

    function test_indexOutOfBounds_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(3e18, 1e18)
        givenBidIsCreated(4e18, 1e18)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionModule.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, 1, 5, _BIDDER);
    }

    function test_success()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, 0, _BIDDER);

        // Assert the bid status
        EncryptedMarginalPrice.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(
            uint8(bidData.status), uint8(EncryptedMarginalPrice.BidStatus.Claimed), "bid status"
        );

        // Assert the refund amount
        assertEq(refundAmount, 2e18, "refund amount");
    }

    function test_success_multipleBids_zeroIndex()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(3e18, 1e18)
        givenBidIsCreated(4e18, 1e18)
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, 1, 0, _BIDDER);

        // Assert the bid status
        EncryptedMarginalPrice.Bid memory bidData = _getBid(_lotId, 1);
        assertEq(
            uint8(bidData.status), uint8(EncryptedMarginalPrice.BidStatus.Claimed), "bid status"
        );

        // Assert the refund amount
        assertEq(refundAmount, 2e18, "refund amount");
    }

    function test_success_multipleBids_nonZeroIndex()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(3e18, 1e18)
        givenBidIsCreated(4e18, 1e18)
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, 2, 1, _BIDDER);

        // Assert the bid status
        EncryptedMarginalPrice.Bid memory bidData = _getBid(_lotId, 2);
        assertEq(
            uint8(bidData.status), uint8(EncryptedMarginalPrice.BidStatus.Claimed), "bid status"
        );

        // Assert the refund amount
        assertEq(refundAmount, 3e18, "refund amount");
    }

    function test_success_multipleBids_lastIndex()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(3e18, 1e18)
        givenBidIsCreated(4e18, 1e18)
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, 3, 2, _BIDDER);

        // Assert the bid status
        EncryptedMarginalPrice.Bid memory bidData = _getBid(_lotId, 3);
        assertEq(
            uint8(bidData.status), uint8(EncryptedMarginalPrice.BidStatus.Claimed), "bid status"
        );

        // Assert the refund amount
        assertEq(refundAmount, 4e18, "refund amount");
    }

    function test_success_multipleRefunds()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(3e18, 1e18)
        givenBidIsCreated(4e18, 1e18)
    {
        // Call the function multiple times
        vm.prank(address(_auctionHouse));
        uint256 refundAmount1 = _module.refundBid(_lotId, 1, 0, _BIDDER);

        EncryptedMarginalPrice.Bid memory bidData1 = _getBid(_lotId, 1);
        assertEq(
            uint8(bidData1.status), uint8(EncryptedMarginalPrice.BidStatus.Claimed), "bid status 1"
        );

        // The third bid should now be in the 0 index because it was swapped with the ejected bid
        vm.prank(address(_auctionHouse));
        uint256 refundAmount3 = _module.refundBid(_lotId, 3, 0, _BIDDER);
        EncryptedMarginalPrice.Bid memory bidData3 = _getBid(_lotId, 3);
        assertEq(
            uint8(bidData3.status), uint8(EncryptedMarginalPrice.BidStatus.Claimed), "bid status 3"
        );

        // The second bid should now be in the 0 index because it was swapped with the ejected bid
        vm.prank(address(_auctionHouse));
        uint256 refundAmount2 = _module.refundBid(_lotId, 2, 0, _BIDDER);
        EncryptedMarginalPrice.Bid memory bidData2 = _getBid(_lotId, 2);
        assertEq(
            uint8(bidData2.status), uint8(EncryptedMarginalPrice.BidStatus.Claimed), "bid status 2"
        );

        // Assert the refund amount
        assertEq(refundAmount1, 2e18, "refund amount 1");
        assertEq(refundAmount2, 3e18, "refund amount 2");
        assertEq(refundAmount3, 4e18, "refund amount 3");
    }

    function test_refundAmount_fuzz(uint256 bidAmount_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 bidAmount = bound(bidAmount_, _minBidAmount, type(uint96).max);

        // Create the bid
        _bidId = _createBid(bidAmount, 1e18);

        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, 0, _BIDDER);

        // Assert the refund amount
        assertEq(refundAmount, bidAmount, "refund amount");
    }

    function test_refundAmount_quoteTokenDecimalsLarger_fuzz(uint256 bidAmount_)
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 bidAmount = bound(bidAmount_, _minBidAmount, type(uint96).max);

        // Create the bid
        _bidId = _createBid(bidAmount, 1e18);

        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, 0, _BIDDER);

        // Assert the refund amount
        assertEq(refundAmount, bidAmount, "refund amount");
    }

    function test_refundAmount_quoteTokenDecimalsSmaller_fuzz(uint256 bidAmount_)
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 bidAmount = bound(bidAmount_, _minBidAmount, type(uint96).max);

        // Create the bid
        _bidId = _createBid(bidAmount, 1e18);

        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, 0, _BIDDER);

        // Assert the refund amount
        assertEq(refundAmount, bidAmount, "refund amount");
    }

    function test_gasUsage_backToFront()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
    {
        // Refund each bid and measure gas usage
        for (uint256 i = 10; i > 0; i--) {
            uint256 gasStart = gasleft();
            vm.prank(address(_auctionHouse));
            _module.refundBid(_lotId, uint64(i), i - 1, _BIDDER);
            console2.log("Gas used for refund: ", gasStart - gasleft());
        }
    }

    function test_gasUsage_frontToBack()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
        givenBidIsCreated(2e18, 1e18)
    {
        // Refund each bid and measure gas usage, go halfway and then back
        for (uint256 i = 0; i < 5; i++) {
            uint256 gasStart = gasleft();
            vm.prank(address(_auctionHouse));
            _module.refundBid(_lotId, uint64(i + 1), i, _BIDDER);
            console2.log("Gas used for refund: ", gasStart - gasleft());
        }

        for (uint256 i = 4; i > 0; i--) {
            uint256 gasStart = gasleft();
            vm.prank(address(_auctionHouse));
            _module.refundBid(_lotId, uint64(10 - i), i, _BIDDER);
            console2.log("Gas used for refund: ", gasStart - gasleft());
        }
    }
}
