// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleClaimBidsTest is EmpaModuleTest {
    uint96 internal constant _BID_AMOUNT = 8e18;
    uint96 internal constant _BID_AMOUNT_OUT = 4e18;

    uint96 internal constant _BID_AMOUNT_UNSUCCESSFUL = 1e18;
    uint96 internal constant _BID_AMOUNT_OUT_UNSUCCESSFUL = 2e18;

    uint96 internal constant _BID_PRICE_TWO_AMOUNT = 4e18;
    uint96 internal constant _BID_PRICE_TWO_AMOUNT_OUT = 2e18;

    uint96 internal constant _BID_PRICE_FOUR_AMOUNT = 8e18;
    uint96 internal constant _BID_PRICE_FOUR_AMOUNT_OUT = 2e18;

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
    // [X] given the bid is not successful
    //  [X] given the quote token decimals are larger
    //   [X] it returns the exact bid amount
    //  [X] given the quote token decimals are smaller
    //   [X] it returns the exact bid amount
    //  [X] it returns the refund details and updates the bid status
    // [X] given the quote token decimals are larger
    //  [X] it returns the exact payout
    // [X] given the quote token decimals are smaller
    //  [X] it returns the exact payout
    // [X] it returns the payout and updates the bid status
    // [X] given there are multiple bids with the same marginal price
    //  [X] given the lot is over-capacity, without partial fill
    //   [X] when the bid has a higher marginal price
    //    [X] it returns the exact payout
    //   [X] when the bid is the last one to be settled
    //    [X] it returns the exact payout
    //   [X] when the bid has the same marginal price and is after the last one to be settled
    //    [X] it returns the exact bid amount
    //   [X] when the bid has a lower marginal price
    //    [X] it returns the exact bid amount

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

    function test_unsuccessfulBid_fuzz(uint96 bidAmountIn_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        uint96 minFillAmount = _MIN_FILL_PERCENT * _LOT_CAPACITY / 1e5;
        // Bound the amounts
        uint96 bidAmountIn = uint96(bound(bidAmountIn_, 1e18, minFillAmount - 1)); // Ensures that it cannot settle even at minimum price
        uint96 bidAmountOut = 1e18; // at minimum price

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
        // auction is settled at marginal price of 1.6, so payout is 8 / 1.6 = 5
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(5e18), "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: paid");
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(5e18), "bid two: payout");

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

        // auction is settled at marginal price of 1.6, so payout is 8 / 1.6 = 5
        uint96 amountOut = 5e18;

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(amountOut));

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO);
        assertEq(bidClaimTwo.referrer, _REFERRER);
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(amountOut));

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

        // auction is settled at marginal price of 1.6, so payout is 8 / 1.6 = 5
        uint96 amountOut = 5e18;

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER);
        assertEq(bidClaimOne.referrer, _REFERRER);
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(amountOut));

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO);
        assertEq(bidClaimTwo.referrer, _REFERRER);
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(amountOut));

        assertEq(bidClaims.length, 2);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_successfulBid_marginalPriceRounding()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(12e18 - 1, _BID_AMOUNT_OUT) // Bid price: ~ 3
        givenBidIsCreatedByBidderTwo(_BID_AMOUNT, _BID_AMOUNT_OUT) // Bid price: 2
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Calculate the expected amounts
        uint256 marginalPrice =
            FixedPointMathLib.mulDivUp(uint256(12e18 - 1 + _BID_AMOUNT), _BASE_SCALE, _LOT_CAPACITY);

        uint256 expectedAmountOutOne =
            FixedPointMathLib.mulDivDown(12e18 - 1, _BASE_SCALE, marginalPrice);
        uint256 expectedAmountOutTwo =
            FixedPointMathLib.mulDivDown(_BID_AMOUNT, _BASE_SCALE, marginalPrice);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, 12e18 - 1, "bid one: paid");
        assertEq(bidClaimOne.payout, expectedAmountOutOne, "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT, "bid two: paid");
        assertEq(bidClaimTwo.payout, expectedAmountOutTwo, "bid two: payout");

        assertEq(bidClaims.length, 2, "bid claims length");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
    }

    function test_successfulBid_marginalPriceRounding_capacityExceeded()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(12e18 - 1, _BID_AMOUNT_OUT) // Bid price: ~ 3
        givenBidIsCreatedByBidderTwo(_BID_AMOUNT, _BID_AMOUNT_OUT) // Bid price: 2
        givenBidIsCreated(1e18, 1e18) // Bid price: 1
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Calculate the expected amounts
        uint256 marginalPrice =
            FixedPointMathLib.mulDivUp(uint256(12e18 - 1 + _BID_AMOUNT), _BASE_SCALE, _LOT_CAPACITY);

        uint256 expectedAmountOutOne =
            FixedPointMathLib.mulDivDown(12e18 - 1, _BASE_SCALE, marginalPrice);
        uint256 expectedAmountOutTwo =
            FixedPointMathLib.mulDivDown(_BID_AMOUNT, _BASE_SCALE, marginalPrice);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, 12e18 - 1, "bid one: paid");
        assertEq(bidClaimOne.payout, expectedAmountOutOne, "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT, "bid two: paid");
        assertEq(bidClaimTwo.payout, expectedAmountOutTwo, "bid two: payout");

        Auction.BidClaim memory bidClaimThree = bidClaims[2];
        assertEq(bidClaimThree.bidder, _BIDDER, "bid three: bidder");
        assertEq(bidClaimThree.referrer, _REFERRER, "bid three: referrer");
        assertEq(bidClaimThree.paid, 1e18, "bid three: paid");
        assertEq(bidClaimThree.payout, 0, "bid three: payout");

        assertEq(bidClaims.length, 3, "bid claims length");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidThree = _getBid(_lotId, _bidIds[2]);
        assertEq(
            uint8(bidThree.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed)
        );
    }

    function test_successfulBid_amountIn_fuzz(uint96 bidAmountIn_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        // Bound the amount in
        uint96 bidAmountIn = uint96(bound(bidAmountIn_, _BID_AMOUNT, 12e18)); // Ensures that the price is greater than _MIN_PRICE and bid 2

        // Create the bid
        _createBid(bidAmountIn, _BID_AMOUNT_OUT);
        _createBid(_BIDDER_TWO, _BID_AMOUNT, _BID_AMOUNT_OUT);

        // Wrap up the lot
        _concludeLot();
        _submitPrivateKey();
        _decryptLot();
        _settleLot();

        // Calculate the expected amounts
        uint256 marginalPrice = FixedPointMathLib.mulDivUp(
            uint256(_BID_AMOUNT + bidAmountIn), _BASE_SCALE, _LOT_CAPACITY
        );
        uint256 expectedAmountOutOne =
            FixedPointMathLib.mulDivDown(bidAmountIn, _BASE_SCALE, marginalPrice);
        uint256 expectedAmountOutTwo =
            FixedPointMathLib.mulDivDown(_BID_AMOUNT, _BASE_SCALE, marginalPrice);

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, bidAmountIn, "bid one: paid");
        assertEq(bidClaimOne.payout, expectedAmountOutOne, "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT, "bid two: paid");
        assertEq(bidClaimTwo.payout, expectedAmountOutTwo, "bid two: payout");

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
        uint256 marginalPrice = FixedPointMathLib.mulDivUp(
            uint256(_BID_AMOUNT + bidAmountIn), _BASE_SCALE, _LOT_CAPACITY
        );
        uint256 expectedAmountOutOne =
            FixedPointMathLib.mulDivDown(bidAmountIn, _BASE_SCALE, marginalPrice);
        uint256 expectedAmountOutTwo =
            FixedPointMathLib.mulDivDown(_BID_AMOUNT, _BASE_SCALE, marginalPrice);

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        Auction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, bidAmountIn, "bid one: paid");
        assertEq(bidClaimOne.payout, expectedAmountOutOne, "bid one: payout");

        Auction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT, "bid two: paid");
        assertEq(bidClaimTwo.payout, expectedAmountOutTwo, "bid two: payout");

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
        // auction is settled at minimum price of 1, so payout = paid (scaled to the correct decimals)
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT), "bid one: payout");

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
        // auction is settled at marginal price of 1.6, so payout is 8 / 1.6 = 5
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(5e18));

        assertEq(bidClaims.length, 1);

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bidOne = _getBid(_lotId, 1);
        assertEq(uint8(bidOne.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed));
        EncryptedMarginalPriceAuctionModule.Bid memory bidTwo = _getBid(_lotId, 2);
        assertEq(
            uint8(bidTwo.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted)
        );
    }

    function test_givenLotOverCapacity_higherMarginalPrice()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_FOUR_AMOUNT, _BID_PRICE_FOUR_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Marginal price is 2
        // Bids 1-4 are settled
        // Bid 5 is not settled (based on order of insertion)
        uint64 bidId = 1;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_FOUR_AMOUNT, "paid");
        assertEq(bidClaim.payout, uint256(_BID_PRICE_FOUR_AMOUNT) * 1e18 / 2e18, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }

    function test_givenLotOverCapacity_higherMarginalPrice_beforeLastSettledBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_FOUR_AMOUNT, _BID_PRICE_FOUR_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Marginal price is 2
        // Bids 1, 3-5 are settled
        // Bid 2 is not settled (based on order of insertion)
        uint64 bidId = 4;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, _BID_PRICE_TWO_AMOUNT_OUT, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }

    function test_givenLotOverCapacity_higherMarginalPrice_lastSettledBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_FOUR_AMOUNT, _BID_PRICE_FOUR_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Marginal price is 2
        // Bids 1-4 are settled
        // Bid 5 is not settled (based on order of insertion)
        uint64 bidId = 4;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, _BID_PRICE_TWO_AMOUNT_OUT, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }

    function test_givenLotOverCapacity_higherMarginalPrice_afterLastSettledBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_FOUR_AMOUNT, _BID_PRICE_FOUR_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Marginal price is 2
        // Bids 1-4 are settled
        // Bid 5 is not settled (based on order of insertion)
        uint64 bidId = 5;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, 0, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }

    function test_givenLotOverCapacity_sameMarginalPrice_beforeLastSettledBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Marginal price is 2
        // Bids 1-5 are settled
        // Bid 6 is not settled (based on order of insertion)
        uint64 bidId = 5;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, _BID_PRICE_TWO_AMOUNT_OUT, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }

    function test_givenLotOverCapacity_sameMarginalPrice_lastSettledBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Marginal price is 2
        // Bids 1-5 are settled
        // Bid 6 is not settled (based on order of insertion)
        uint64 bidId = 5;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, _BID_PRICE_TWO_AMOUNT_OUT, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }

    function test_givenLotOverCapacity_sameMarginalPrice_afterSettledBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Marginal price is 2
        // Bids 1-5 are settled
        // Bid 6 is not settled (based on order of insertion)
        uint64 bidId = 6;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, 0, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }

    function test_givenLotOverCapacity_unsuccessfulBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_AMOUNT_UNSUCCESSFUL, _BID_AMOUNT_OUT_UNSUCCESSFUL)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        uint64 bidId = 7;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_AMOUNT_UNSUCCESSFUL, "paid");
        assertEq(bidClaim.payout, 0, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }

    function test_givenLotOverCapacity_unsuccessfulBid_respectsOrdering()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT_UNSUCCESSFUL, _BID_AMOUNT_OUT_UNSUCCESSFUL)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenBidIsCreated(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        uint64 bidId = 1;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (Auction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        Auction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_AMOUNT_UNSUCCESSFUL, "paid");
        assertEq(bidClaim.payout, 0, "payout");

        // Check the bid status
        EncryptedMarginalPriceAuctionModule.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );
    }
}
