// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleRefundBidTest is EmpaModuleTest {
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the bid id is invalid
    //  [X] it reverts
    // [X] when the bidder is not the the bid owner
    //  [X] it reverts
    // [X] given the bid has already been refunded
    //  [X] it reverts
    // [X] given the lot is concluded
    //  [X] it reverts
    // [X] given the lot has been cancelled
    //  [X] it reverts
    // [X] given the lot is decrypted
    //  [X] it reverts
    // [X] given the lot is settled
    //  [X] it reverts
    // [X] given the lot proceeds have been claimed
    //  [X] it reverts
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] it refunds the bid amount and updates the bid status
    // [X] it refunds the exact bid amount

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, _BIDDER);
    }

    function test_invalidBidId_reverts() external givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Auction.Auction_InvalidBidId.selector, _lotId, _bidId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, _BIDDER);
    }

    function test_bidderIsNotBidOwner_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.NotPermitted.selector, address(this)
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, address(this));
    }

    function test_bidAlreadyRefunded_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenBidIsRefunded(_bidId)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Bid_WrongState.selector, _lotId, _bidId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, _BIDDER);
    }

    function test_lotIsConcluded_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, _BIDDER);
    }

    function test_lotIsCancelled_reverts() external givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, _BIDDER);
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
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, _BIDDER);
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
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, _BIDDER);
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
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, _bidId, _BIDDER);
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
        _module.refundBid(_lotId, _bidId, _BIDDER);
    }

    function test_success()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, _BIDDER);

        // Assert the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "bid status"
        );

        // Assert the refund amount
        assertEq(refundAmount, 2e18, "refund amount");
    }

    function test_refundAmount_fuzz(uint96 bidAmount_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        uint96 bidAmount = uint96(bound(bidAmount_, _minBidAmount, type(uint96).max));

        // Create the bid
        _bidId = _createBid(bidAmount, 1e18);

        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, _BIDDER);

        // Assert the refund amount
        assertEq(refundAmount, bidAmount, "refund amount");
    }

    function test_refundAmount_quoteTokenDecimalsLarger_fuzz(uint96 bidAmount_)
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint96 bidAmount = uint96(bound(bidAmount_, _minBidAmount, type(uint96).max));

        // Create the bid
        _bidId = _createBid(bidAmount, 1e18);

        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, _BIDDER);

        // Assert the refund amount
        assertEq(refundAmount, bidAmount, "refund amount");
    }

    function test_refundAmount_quoteTokenDecimalsSmaller_fuzz(uint96 bidAmount_)
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint96 bidAmount = uint96(bound(bidAmount_, _minBidAmount, type(uint96).max));

        // Create the bid
        _bidId = _createBid(bidAmount, 1e18);

        // Call the function
        vm.prank(address(_auctionHouse));
        uint256 refundAmount = _module.refundBid(_lotId, _bidId, _BIDDER);

        // Assert the refund amount
        assertEq(refundAmount, bidAmount, "refund amount");
    }
}
