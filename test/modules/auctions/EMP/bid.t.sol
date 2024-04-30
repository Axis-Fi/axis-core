// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/EMP.sol";
import {Point} from "src/lib/ECIES.sol";

import {EmpTest} from "test/modules/auctions/EMP/EMPTest.sol";

contract EmpBidTest is EmpTest {
    uint256 internal constant _BID_AMOUNT = 2e18;
    uint256 internal constant _BID_AMOUNT_OUT = 1e18;
    uint256 internal constant _BID_AMOUNT_BELOW_MIN = 1e14;

    uint256 internal constant _LOT_CAPACITY_OVERFLOW = type(uint256).max - 10;

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot has not started
    //  [X] it reverts
    // [X] when the lot has concluded
    //  [X] it reverts
    // [X] when the lot is in the settlement period
    //  [X] it reverts
    // [X] when the lot has been settled
    //  [X] it reverts
    // [X] when the lot has been aborted
    //  [X] it reverts
    // [X] when the lot has been cancelled
    //  [X] it reverts
    // [X] when the auction data is in an invalid format
    //  [X] it reverts
    // [X] when the implied amount out is less than the minimum bid size
    //  [X] it reverts
    // [X] when the bid public key is invalid
    //  [X] it reverts
    // [X] when the bid amount is greater than uint96 max
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotNotStarted_reverts() public givenLotIsCreated {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotConcluded_reverts() public givenLotIsCreated givenLotHasConcluded {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotInSettlePeriod_reverts()
        public
        givenLotIsCreated
        givenLotHasConcluded
        givenDuringLotSettlePeriod
    {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotAborted_reverts()
        public
        givenLotIsCreated
        givenLotSettlePeriodHasPassed
        givenLotIsAborted
    {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_lotCancelled_reverts() public givenLotIsCreated givenLotIsCancelled {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
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

    function test_amountLessThanMinimumBidSize_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        // Prepare the inputs
        bytes memory bidData = _createBidData(_BID_AMOUNT_BELOW_MIN, _BID_AMOUNT_OUT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT_BELOW_MIN, bidData);
    }

    function test_amountLessThanMinimumBidSize_quoteTokenDecimalsLarger_reverts()
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(
            _lotId, _BIDDER, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT_BELOW_MIN), bidData
        );
    }

    function test_amountLessThanMinimumBidSize_quoteTokenDecimalsSmaller_reverts()
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_AmountLessThanMinimum.selector);
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
            abi.encodeWithSelector(EncryptedMarginalPrice.Auction_InvalidKey.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidData);
    }

    function test_bidAmountGreaterThanUint96Max_reverts(uint256 amountIn_)
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 amountIn = bound(amountIn_, uint256(2 ** 96), type(uint256).max);

        // Prepare the inputs
        bytes memory bidData = _createBidData(amountIn, _BID_AMOUNT_OUT);

        // Expect revert
        vm.expectRevert();

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, amountIn, bidData);
    }

    function test_success() public givenLotIsCreated givenLotHasStarted {
        uint256 encryptedAmountOut = _encryptBid(_lotId, _BIDDER, _BID_AMOUNT, _BID_AMOUNT_OUT);

        // Call the function
        uint64 bidId = _createBid(_BID_AMOUNT, _BID_AMOUNT_OUT);

        // Assert the state
        EncryptedMarginalPrice.Bid memory bidData = _getBid(_lotId, bidId);
        assertEq(bidData.bidder, _BIDDER, "bidder");
        assertEq(bidData.amount, _BID_AMOUNT, "amount");
        assertEq(bidData.minAmountOut, 0, "amountOut");
        assertEq(bidData.referrer, _REFERRER, "referrer");
        assertEq(uint8(bidData.status), uint8(EncryptedMarginalPrice.BidStatus.Submitted), "status");

        EncryptedMarginalPrice.EncryptedBid memory encryptedBidData =
            _getEncryptedBid(_lotId, bidId);
        assertEq(encryptedBidData.encryptedAmountOut, encryptedAmountOut, "encryptedAmountOut");
        assertEq(encryptedBidData.bidPubKey.x, _bidPublicKey.x, "bidPubKey.x");
        assertEq(encryptedBidData.bidPubKey.y, _bidPublicKey.y, "bidPubKey.y");

        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextBidId, 2, "nextBidId");
    }
}
