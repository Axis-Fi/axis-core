// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleClaimBidsTest is EmpaModuleTest {
    uint96 internal constant _BID_AMOUNT = 8e18;
    uint96 internal constant _BID_AMOUNT_OUT = 4e18;

    uint96 internal constant _BID_AMOUNT_UNSUCCESSFUL = 1e18;
    uint96 internal constant _BID_AMOUNT_OUT_UNSUCCESSFUL = 2e18;

    address internal constant _BIDDER_TWO = address(0x20);

    // ============ Modifiers ============ //

    modifier givenBidIsCreatedByBidderTwo(uint96 amountIn_, uint96 amountOut_) {
        _createBid(_BIDDER_TWO, amountIn_, amountOut_);
        _;
    }

    // ============ Test Cases ============ //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when any bid id is invalid
    //  [X] it reverts
    // [X] given any bid has already been claimed
    //  [X] it reverts
    // [X] given the lot is not settled
    //  [X] it reverts
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] given the minAmountOut is 0
    //  [X] it refunds the bid
    // [X] given the bids have different outcomes
    //  [X] it returns the correct amounts
    // [X] given other bids are not claimed
    //  [X] it does not alter the other bids
    // [X] it refunds the exact bid amount
    // [X] it sends the payout

    function test_invalidLotId_reverts() external {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimBids(_lotId, _bidIds);
    }

    function test_invalidBidId_reverts()
        external
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidBidId.selector, _lotId, 1);
        vm.expectRevert(err);

        _bidIds.push(1);
        _bidIds.push(2);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimBids(_lotId, _bidIds);
    }

    function test_anyInvalidBidId_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidBidId.selector, _lotId, 2);
        vm.expectRevert(err);

        _bidIds.push(2);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimBids(_lotId, _bidIds);
    }

    function test_bidAlreadyClaimed_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
        givenBidIsClaimed(_bidId)
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Bid_WrongState.selector, _lotId, _bidId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimBids(_lotId, _bidIds);
    }

    function test_lotNotSettled_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimBids(_lotId, _bidIds);
    }

    function test_callerIsNotParent_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.claimBids(_lotId, _bidIds);
    }

    function test_unsuccessfulBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(
            _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_UNSUCCESSFUL)
        )
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_UNSUCCESSFUL)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, _BID_AMOUNT_UNSUCCESSFUL);
        assertEq(bidClaimOne.payout, 0);

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO);
        assertEq(bidClaimTwo.referrer, _REFERRER);
        assertEq(bidClaimTwo.paid, _BID_AMOUNT_UNSUCCESSFUL);
        assertEq(bidClaimTwo.payout, 0);

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_unsuccessfulBid_fuzz(
        uint96 bidAmountIn_,
        uint96 bidAmountOut_
    ) external givenLotIsCreated givenLotHasStarted {
        uint96 minFillAmount = _MIN_FILL_PERCENT * _LOT_CAPACITY / 1e5;
        // Bound the amounts
        uint96 bidAmountIn = uint96(bound(bidAmountIn_, 1e18, 10e18));
        uint96 bidAmountOut = uint96(bound(bidAmountOut_, 1e18, minFillAmount - 1)); // Ensures that it will not be a winning bid

        // Create the bid
        _createBid(bidAmountIn, bidAmountOut);
        _createBid(_BIDDER_TWO, _BID_AMOUNT_UNSUCCESSFUL, _BID_AMOUNT_OUT_UNSUCCESSFUL);

        // Wrap up the lot
        _concludeLot();
        _submitPrivateKey();
        _decryptLot();
        _settleLot();

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, bidAmountIn);
        assertEq(bidClaimOne.payout, 0);

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO);
        assertEq(bidClaimTwo.referrer, _REFERRER);
        assertEq(bidClaimTwo.paid, _BID_AMOUNT_UNSUCCESSFUL);
        assertEq(bidClaimTwo.payout, 0);

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_unsuccessfulBid_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(
            _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_UNSUCCESSFUL)
        )
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_UNSUCCESSFUL)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL));
        assertEq(bidClaimOne.payout, 0);

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO);
        assertEq(bidClaimTwo.referrer, _REFERRER);
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL));
        assertEq(bidClaimTwo.payout, 0);

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_unsuccessfulBid_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(
            _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_UNSUCCESSFUL)
        )
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_UNSUCCESSFUL)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL));
        assertEq(bidClaimOne.payout, 0);

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO);
        assertEq(bidClaimTwo.referrer, _REFERRER);
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL));
        assertEq(bidClaimTwo.payout, 0);

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_successfulBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT), "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: paid");
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT), "bid two: payout");

        assertEq(bidClaims.length, 2, "bid claims length");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_successfulBid_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT));

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO);
        assertEq(bidClaimTwo.referrer, _REFERRER);
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT));

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_successfulBid_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT));

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO);
        assertEq(bidClaimTwo.referrer, _REFERRER);
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT));

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_successfulBid_amountIn_fuzz(uint96 bidAmountIn_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        // Bound the amount in
        uint96 bidAmountIn = uint96(bound(bidAmountIn_, _BID_AMOUNT, 10e20)); // Ensures that the price is greater than _MIN_PRICE and bid 2

        // Create the bid
        _createBid(bidAmountIn, _BID_AMOUNT_OUT);
        _createBid(_BIDDER_TWO, _BID_AMOUNT, _BID_AMOUNT_OUT);

        // Wrap up the lot
        _concludeLot();
        _submitPrivateKey();
        _decryptLot();
        _settleLot();

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(bidAmountIn), "bid one: paid");
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT), "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: paid");
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT), "bid two: payout");

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_successfulBid_amountOut_fuzz(uint96 bidAmountOut_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        // Bound the amount out
        uint96 bidAmountOut = uint96(bound(bidAmountOut_, _BID_AMOUNT_OUT, 5e18)); // Ensures that the lot settles but is not overfilled
        uint96 bidAmountIn = 11e18; // Ensures that the price is greater than bid 2

        // Create the bid
        _createBid(bidAmountIn, bidAmountOut);
        _createBid(_BIDDER_TWO, _BID_AMOUNT, _BID_AMOUNT_OUT);

        // Wrap up the lot
        _concludeLot();
        _submitPrivateKey();
        _decryptLot();
        _settleLot();

        // Calculate the payout for bid one
        uint256 bidOnePayout = uint256(bidAmountIn) * 1e18 / 2e18;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(bidAmountIn), "bid one: paid");
        assertEq(bidClaimOne.payout, bidOnePayout, "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: paid");
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT), "bid two: payout");

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_mixtureBids()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_UNSUCCESSFUL)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT), "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(
            bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid two: paid"
        );
        assertEq(bidClaimTwo.payout, 0, "bid two: payout");

        assertEq(bidClaims.length, 2, "bid claims length");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_unclaimedBids()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = 1;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT_OUT));

        assertEq(bidClaims.length, 1);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, 1);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, 2);
        assertEq(
            uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted)
        );
    }
}