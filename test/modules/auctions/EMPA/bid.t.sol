// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";
import {Point} from "src/lib/ECIES.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleBidTest is EmpaModuleTest {
    uint96 internal constant _BID_AMOUNT = 2e18;
    uint96 internal constant _BID_AMOUNT_OUT = 1e18;
    uint96 internal constant _BID_AMOUNT_BELOW_MIN = 1e16;

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot has not started
    //  [X] it reverts
    // [X] when the lot has concluded
    //  [X] it reverts
    // [X] when the lot has been settled
    //  [X] it reverts
    // [X] when the lot has been cancelled
    //  [X] it reverts
    // [X] when the lot proceeds have been claimed
    //  [X] it reverts
    // [X] when the auction data is in an invalid format
    //  [X] it reverts
    // [X] when the implied amount out is less than the minimum bid size
    //  [X] it reverts
    // [X] when the bid public key is invalid
    //  [X] it reverts
    // [X] it stores the bid data

    function test_notParent_reverts() public {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_invalidLotId_reverts() public {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotNotStarted_reverts() public givenLotIsCreated {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotConcluded_reverts() public givenLotIsCreated givenLotHasConcluded {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotSettled_reverts()
        public
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
    {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotProceedsClaimed_reverts()
        public
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
        givenLotProceedsAreClaimed
    {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotCancelled_reverts() public givenLotIsCreated givenLotIsCancelled {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_invalidBidData_reverts() public givenLotIsCreated givenLotHasStarted {
        // Prepare the inputs
        bytes memory bidData = abi.encodePacked(uint256(0));

        // Expect revert
        vm.expectRevert();

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_amountOutLessThanMinimumBidSize_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT_BELOW_MIN, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT_BELOW_MIN, bidData);
    }

    function test_amountOutLessThanMinimumBidSize_quoteTokenDecimalsLarger_reverts()
        public
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Prepare the inputs
        bytes memory bidData = _createBidData(
            _scaleQuoteTokenAmount(_BID_AMOUNT_BELOW_MIN), _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        );

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(
            _lotId, _BIDDER, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT_BELOW_MIN), bidData
        );
    }

    function test_amountOutLessThanMinimumBidSize_quoteTokenDecimalsSmaller_reverts()
        public
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Prepare the inputs
        bytes memory bidData = _createBidData(
            _scaleQuoteTokenAmount(_BID_AMOUNT_BELOW_MIN), _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        );

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(
            _lotId, _BIDDER, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT_BELOW_MIN), bidData
        );
    }

    function test_invalidBidPublicKey_reverts() public givenLotIsCreated givenLotHasStarted {
        // Prepare the inputs
        uint256 encryptedAmountOut = _encryptBid(_lotId, _BIDDER, _BID_AMOUNT, _BID_AMOUNT_OUT);
        bytes memory bidData = abi.encode(encryptedAmountOut, Point({x: 0, y: 0}));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuctionModule.Auction_InvalidKey.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_success() public givenLotIsCreated givenLotHasStarted {
        uint256 encryptedAmountOut = _encryptBid(_lotId, _BIDDER, _BID_AMOUNT, _BID_AMOUNT_OUT);

        // Call the function
        uint64 bidId = _createBid(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Assert the state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, bidId);
        assertEq(bidData.bidder, _BIDDER, "bidder");
        assertEq(bidData.amount, _BID_AMOUNT, "amount");
        assertEq(bidData.minAmountOut, 0, "amountOut");
        assertEq(bidData.referrer, _REFERRER, "referrer");
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Submitted),
            "status"
        );

        EncryptedMarginalPriceAuctionModule.EncryptedBid memory encryptedBidData =
            _getEncryptedBid(_lotId, bidId);
        assertEq(encryptedBidData.encryptedAmountOut, encryptedAmountOut, "encryptedAmountOut");
        assertEq(encryptedBidData.bidPubKey.x, _bidPublicKey.x, "bidPubKey.x");
        assertEq(encryptedBidData.bidPubKey.y, _bidPublicKey.y, "bidPubKey.y");

        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextBidId, 2, "nextBidId");
    }
}
