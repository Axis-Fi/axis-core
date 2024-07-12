// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {FixedPointMathLib as Math} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IEncryptedMarginalPrice} from "src/interfaces/modules/auctions/IEncryptedMarginalPrice.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/batch/EMP.sol";
import {IBatchAuction} from "src/interfaces/modules/IBatchAuction.sol";

import {EmpTest} from "test/modules/auctions/EMP/EMPTest.sol";

contract EmpClaimBidsTest is EmpTest {
    uint256 internal constant _BID_AMOUNT = 8e18;
    uint256 internal constant _BID_AMOUNT_OUT = 4e18;

    uint256 internal constant _BID_AMOUNT_UNSUCCESSFUL = 1e18;
    uint256 internal constant _BID_AMOUNT_OUT_UNSUCCESSFUL = 2e18;

    uint256 internal constant _BID_PRICE_TWO_AMOUNT = 4e18;
    uint256 internal constant _BID_PRICE_TWO_AMOUNT_OUT = 2e18;

    uint256 internal constant _BID_PRICE_FOUR_AMOUNT = 8e18;
    uint256 internal constant _BID_PRICE_FOUR_AMOUNT_OUT = 2e18;

    address internal constant _BIDDER_TWO = address(0x20);

    // ============ Modifiers ============ //

    modifier givenBidIsCreatedByBidderTwo(uint256 amountIn_, uint256 amountOut_) {
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
    // [X] given the bid is a partial fill
    //  [X] it returns the correct paid and payout amounts
    // [X] given the seller has claimed proceeds
    //  [X] it refunds the bid
    // [X] given the seller has claimed proceeds
    //  [X] it refunds the bid
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
    // [X] given the lot has been aborted
    //  [X] all bids are refunded
    // [X] given the bid could not be decrypted
    //  [X] it refunds the bid

    function test_invalidLotId_reverts() external {
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, _lotId);
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
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_InvalidBidId.selector, _lotId, 1);
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
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_InvalidBidId.selector, _lotId, 2);
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
        bytes memory err =
            abi.encodeWithSelector(IEncryptedMarginalPrice.Bid_WrongState.selector, _lotId, _bidId);
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
        bytes memory err =
            abi.encodeWithSelector(IEncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _BID_AMOUNT_UNSUCCESSFUL, "bid one: paid");
        assertEq(bidClaimOne.payout, 0, "bid one: payout");
        assertEq(bidClaimOne.refund, _BID_AMOUNT_UNSUCCESSFUL, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT_UNSUCCESSFUL, "bid two: paid");
        assertEq(bidClaimTwo.payout, 0, "bid two: payout");
        assertEq(bidClaimTwo.refund, _BID_AMOUNT_UNSUCCESSFUL, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid count");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
    }

    function test_unsuccessfulBid_fuzz(uint256 bidAmountIn_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 minFillAmount = _MIN_FILL_PERCENT * _LOT_CAPACITY / 100e2;
        // Bound the amounts
        uint256 bidAmountIn = bound(bidAmountIn_, 1e18, minFillAmount - 1); // Ensures that it cannot settle even at minimum price
        uint256 bidAmountOut = 1e18; // at minimum price

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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, bidAmountIn, "bid one: paid");
        assertEq(bidClaimOne.payout, 0, "bid one: payout");
        assertEq(bidClaimOne.refund, bidAmountIn, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT_UNSUCCESSFUL, "bid two: paid");
        assertEq(bidClaimTwo.payout, 0, "bid two: payout");
        assertEq(bidClaimTwo.refund, _BID_AMOUNT_UNSUCCESSFUL, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid count");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(
            bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid one: paid"
        );
        assertEq(bidClaimOne.payout, 0, "bid one: payout");
        assertEq(
            bidClaimOne.refund, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid one: refund"
        );

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(
            bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid two: paid"
        );
        assertEq(bidClaimTwo.payout, 0, "bid two: payout");
        assertEq(
            bidClaimTwo.refund, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid two: refund"
        );

        assertEq(bidClaims.length, 2, "bid count");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(
            bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid one: paid"
        );
        assertEq(bidClaimOne.payout, 0, "bid one: payout");
        assertEq(
            bidClaimOne.refund, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid one: refund"
        );

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(
            bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid two: paid"
        );
        assertEq(bidClaimTwo.payout, 0, "bid two: payout");
        assertEq(
            bidClaimTwo.refund, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid two: refund"
        );

        assertEq(bidClaims.length, 2, "bid count");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        // auction is settled at marginal price of 1.6, so payout is 8 / 1.6 = 5
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(5e18), "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: paid");
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(5e18), "bid two: payout");
        assertEq(bidClaimTwo.refund, 0, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid claims length");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // auction is settled at marginal price of 1.6, so payout is 8 / 1.6 = 5
        uint256 amountOut = 5e18;

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(amountOut), "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: paid");
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(amountOut), "bid two: payout");
        assertEq(bidClaimTwo.refund, 0, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid count");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // auction is settled at marginal price of 1.6, so payout is 8 / 1.6 = 5
        uint256 amountOut = 5e18;

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(amountOut), "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: paid");
        assertEq(bidClaimTwo.payout, _scaleBaseTokenAmount(amountOut), "bid two: payout");
        assertEq(bidClaimTwo.refund, 0, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid count");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
    }

    function test_successfulBid_auctionAborted()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenBidIsCreatedByBidderTwo(
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
        givenLotIsAborted
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        assertEq(bidClaimOne.payout, 0, "bid one: payout");
        assertEq(bidClaimOne.refund, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: paid");
        assertEq(bidClaimTwo.payout, 0, "bid two: payout");
        assertEq(bidClaimTwo.refund, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid two: refund");

        assertEq(bidClaims.length, 2, "bid claims length");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Calculate the expected amounts
        uint256 marginalPrice =
            Math.mulDivUp(uint256(12e18 - 1 + _BID_AMOUNT), _BASE_SCALE, _LOT_CAPACITY);

        uint256 expectedAmountOutOne = Math.mulDiv(12e18 - 1, _BASE_SCALE, marginalPrice);
        uint256 expectedAmountOutTwo = Math.mulDiv(_BID_AMOUNT, _BASE_SCALE, marginalPrice);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, 12e18 - 1, "bid one: paid");
        assertEq(bidClaimOne.payout, expectedAmountOutOne, "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT, "bid two: paid");
        assertEq(bidClaimTwo.payout, expectedAmountOutTwo, "bid two: payout");
        assertEq(bidClaimTwo.refund, 0, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid claims length");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Calculate the expected amounts
        uint256 marginalPrice =
            Math.mulDivUp(uint256(12e18 - 1 + _BID_AMOUNT), _BASE_SCALE, _LOT_CAPACITY);

        uint256 expectedAmountOutOne = Math.mulDiv(12e18 - 1, _BASE_SCALE, marginalPrice);
        uint256 expectedAmountOutTwo = Math.mulDiv(_BID_AMOUNT, _BASE_SCALE, marginalPrice);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, 12e18 - 1, "bid one: paid");
        assertEq(bidClaimOne.payout, expectedAmountOutOne, "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT, "bid two: paid");
        assertEq(bidClaimTwo.payout, expectedAmountOutTwo, "bid two: payout");
        assertEq(bidClaimTwo.refund, 0, "bid two: refund");

        IBatchAuction.BidClaim memory bidClaimThree = bidClaims[2];
        assertEq(bidClaimThree.bidder, _BIDDER, "bid three: bidder");
        assertEq(bidClaimThree.referrer, _REFERRER, "bid three: referrer");
        assertEq(bidClaimThree.paid, 1e18, "bid three: paid");
        assertEq(bidClaimThree.payout, 0, "bid three: payout");
        assertEq(bidClaimThree.refund, 1e18, "bid three: refund");

        assertEq(bidClaims.length, 3, "bid claims length");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );
        EncryptedMarginalPrice.Bid memory bidThree = _getBid(_lotId, _bidIds[2]);
        assertEq(
            uint8(bidThree.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid three: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");

        IBatchAuction.BidClaim memory bidClaimThreeView = _module.getBidClaim(_lotId, _bidIds[2]);
        assertEq(bidClaimThreeView.bidder, bidClaimThree.bidder, "bid three: bidder");
        assertEq(bidClaimThreeView.referrer, bidClaimThree.referrer, "bid three: referrer");
        assertEq(bidClaimThreeView.paid, bidClaimThree.paid, "bid three: paid");
        assertEq(bidClaimThreeView.payout, bidClaimThree.payout, "bid three: payout");
        assertEq(bidClaimThreeView.refund, bidClaimThree.refund, "bid three: refund");
    }

    function test_successfulBid_amountIn_fuzz(uint256 bidAmountIn_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        // Bound the amount in
        uint256 bidAmountIn = bound(bidAmountIn_, _BID_AMOUNT, 12e18); // Ensures that the price is greater than _MIN_PRICE and bid 2

        // Create the bid
        _createBid(bidAmountIn, _BID_AMOUNT_OUT);
        _createBid(_BIDDER_TWO, _BID_AMOUNT, _BID_AMOUNT_OUT);

        // Wrap up the lot
        _concludeLot();
        _submitPrivateKey();
        _decryptLot();
        _settleLot();

        // Calculate the expected amounts
        uint256 marginalPrice =
            Math.mulDivUp(uint256(_BID_AMOUNT + bidAmountIn), _BASE_SCALE, _LOT_CAPACITY);
        uint256 expectedAmountOutOne = Math.mulDiv(bidAmountIn, _BASE_SCALE, marginalPrice);
        uint256 expectedAmountOutTwo = Math.mulDiv(_BID_AMOUNT, _BASE_SCALE, marginalPrice);

        // Call the function
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, bidAmountIn, "bid one: paid");
        assertEq(bidClaimOne.payout, expectedAmountOutOne, "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT, "bid two: paid");
        assertEq(bidClaimTwo.payout, expectedAmountOutTwo, "bid two: payout");
        assertEq(bidClaimTwo.refund, 0, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid count");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
    }

    function test_successfulBid_amountOut_fuzz(uint256 bidAmountOut_)
        external
        givenLotIsCreated
        givenLotHasStarted
    {
        // Bound the amount out
        uint256 bidAmountOut = bound(bidAmountOut_, _BID_AMOUNT_OUT, 5e18); // Ensures that the lot settles but is not overfilled
        uint256 bidAmountIn = 11e18; // Ensures that the price is greater than bid 2

        // Create the bid
        _createBid(bidAmountIn, bidAmountOut);
        _createBid(_BIDDER_TWO, _BID_AMOUNT, _BID_AMOUNT_OUT);

        // Wrap up the lot
        _concludeLot();
        _submitPrivateKey();
        _decryptLot();
        _settleLot();

        // Calculate the payout for bid one
        uint256 marginalPrice =
            Math.mulDivUp(uint256(_BID_AMOUNT + bidAmountIn), _BASE_SCALE, _LOT_CAPACITY);
        uint256 expectedAmountOutOne = Math.mulDiv(bidAmountIn, _BASE_SCALE, marginalPrice);
        uint256 expectedAmountOutTwo = Math.mulDiv(_BID_AMOUNT, _BASE_SCALE, marginalPrice);

        // Call the function
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, bidAmountIn, "bid one: paid");
        assertEq(bidClaimOne.payout, expectedAmountOutOne, "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, _BID_AMOUNT, "bid two: paid");
        assertEq(bidClaimTwo.payout, expectedAmountOutTwo, "bid two: payout");
        assertEq(bidClaimTwo.refund, 0, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid count");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        // auction is settled at minimum price of 1, so payout = paid (scaled to the correct decimals)
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT), "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER_TWO, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(
            bidClaimTwo.paid, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid two: paid"
        );
        assertEq(bidClaimTwo.payout, 0, "bid two: payout");
        assertEq(
            bidClaimTwo.refund, _scaleQuoteTokenAmount(_BID_AMOUNT_UNSUCCESSFUL), "bid two: refund"
        );

        assertEq(bidClaims.length, 2, "bid claims length");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        // auction is settled at marginal price of 1.6, so payout is 8 / 1.6 = 5
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(5e18), "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        assertEq(bidClaims.length, 1);

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, 1);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, 2);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Decrypted),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_FOUR_AMOUNT, "paid");
        assertEq(bidClaim.payout, uint256(_BID_PRICE_FOUR_AMOUNT) * 1e18 / 2e18, "payout");
        assertEq(bidClaim.refund, 0, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
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
        // Bids 1-4 are settled
        // Bid 5 is not settled (based on order of insertion)
        uint64 bidId = 3;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, _BID_PRICE_TWO_AMOUNT_OUT, "payout");
        assertEq(bidClaim.refund, 0, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, _BID_PRICE_TWO_AMOUNT_OUT, "payout");
        assertEq(bidClaim.refund, 0, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, 0, "payout");
        assertEq(bidClaim.refund, _BID_PRICE_TWO_AMOUNT, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
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
        uint64 bidId = 4;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, _BID_PRICE_TWO_AMOUNT_OUT, "payout");
        assertEq(bidClaim.refund, 0, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, _BID_PRICE_TWO_AMOUNT_OUT, "payout");
        assertEq(bidClaim.refund, 0, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
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
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_PRICE_TWO_AMOUNT, "paid");
        assertEq(bidClaim.payout, 0, "payout");
        assertEq(bidClaim.refund, _BID_PRICE_TWO_AMOUNT, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
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
        // Bids 1-5 successful
        // Bids 6-7 unsuccessful
        uint64 bidId = 7;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_AMOUNT_UNSUCCESSFUL, "paid");
        assertEq(bidClaim.payout, 0, "payout");
        assertEq(bidClaim.refund, _BID_AMOUNT_UNSUCCESSFUL, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
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
        // Bids 2-5 successful
        // Bids 1, 7 unsuccessful
        uint64 bidId = 1;

        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId;

        // Call the function
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaim = bidClaims[0];
        assertEq(bidClaim.bidder, _BIDDER, "bidder");
        assertEq(bidClaim.referrer, _REFERRER, "referrer");
        assertEq(bidClaim.paid, _BID_AMOUNT_UNSUCCESSFUL, "paid");
        assertEq(bidClaim.payout, 0, "payout");
        assertEq(bidClaim.refund, _BID_AMOUNT_UNSUCCESSFUL, "refund");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bid = _getBid(_lotId, bidId);
        assertEq(uint8(bid.status), uint8(IEncryptedMarginalPrice.BidStatus.Claimed), "status");

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaim.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaim.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaim.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaim.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaim.refund, "bid one: refund");
    }

    function test_givenBidNotDecrypted()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenBidIsCreated(type(uint96).max, 1e17) // Will cause the price to overflow
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, _bidIds);

        // Check the result
        IBatchAuction.BidClaim memory bidClaimOne = bidClaims[0];
        assertEq(bidClaimOne.bidder, _BIDDER, "bid one: bidder");
        assertEq(bidClaimOne.referrer, _REFERRER, "bid one: referrer");
        assertEq(bidClaimOne.paid, _scaleQuoteTokenAmount(_BID_AMOUNT), "bid one: paid");
        // auction is settled at minimum price of 1, so payout = paid (scaled to the correct decimals)
        assertEq(bidClaimOne.payout, _scaleBaseTokenAmount(_BID_AMOUNT), "bid one: payout");
        assertEq(bidClaimOne.refund, 0, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwo = bidClaims[1];
        assertEq(bidClaimTwo.bidder, _BIDDER, "bid two: bidder");
        assertEq(bidClaimTwo.referrer, _REFERRER, "bid two: referrer");
        assertEq(bidClaimTwo.paid, type(uint96).max, "bid two: paid");
        assertEq(bidClaimTwo.payout, 0, "bid two: payout");
        assertEq(bidClaimTwo.refund, type(uint96).max, "bid two: refund");

        assertEq(bidClaims.length, 2, "bid claims length");

        // Check the bid status
        EncryptedMarginalPrice.Bid memory bidOne = _getBid(_lotId, _bidIds[0]);
        assertEq(
            uint8(bidOne.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid one: status"
        );
        EncryptedMarginalPrice.Bid memory bidTwo = _getBid(_lotId, _bidIds[1]);
        assertEq(
            uint8(bidTwo.status),
            uint8(IEncryptedMarginalPrice.BidStatus.Claimed),
            "bid two: status"
        );

        // Check that the BidClaim data matches
        IBatchAuction.BidClaim memory bidClaimOneView = _module.getBidClaim(_lotId, _bidIds[0]);
        assertEq(bidClaimOneView.bidder, bidClaimOne.bidder, "bid one: bidder");
        assertEq(bidClaimOneView.referrer, bidClaimOne.referrer, "bid one: referrer");
        assertEq(bidClaimOneView.paid, bidClaimOne.paid, "bid one: paid");
        assertEq(bidClaimOneView.payout, bidClaimOne.payout, "bid one: payout");
        assertEq(bidClaimOneView.refund, bidClaimOne.refund, "bid one: refund");

        IBatchAuction.BidClaim memory bidClaimTwoView = _module.getBidClaim(_lotId, _bidIds[1]);
        assertEq(bidClaimTwoView.bidder, bidClaimTwo.bidder, "bid two: bidder");
        assertEq(bidClaimTwoView.referrer, bidClaimTwo.referrer, "bid two: referrer");
        assertEq(bidClaimTwoView.paid, bidClaimTwo.paid, "bid two: paid");
        assertEq(bidClaimTwoView.payout, bidClaimTwo.payout, "bid two: payout");
        assertEq(bidClaimTwoView.refund, bidClaimTwo.refund, "bid two: refund");
    }

    function test_below_price_precision_totalCorrect()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(4e18 + 1, 2e18) // bidId = 1
        givenBidIsCreated(4e18 + 2, 2e18) // bidId = 2
        givenBidIsCreated(4e18 + 2, 2e18) // bidId = 3
        givenBidIsCreated(4e18 + 2, 2e18) // bidId = 4
        givenBidIsCreated(4e18 + 2, 2e18) // bidId = 5
        givenBidIsCreated(4e18 + 2, 2e18) // bidId = 6
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);

        console2.log("marginal price     ==>  ", auctionData.marginalPrice);
        console2.log("marginal bid id    ==>  ", auctionData.marginalBidId);
        console2.log("");

        // Construct array to claim all bids at once
        uint64[] memory bidIds = new uint64[](6);
        for (uint64 i = 1; i <= 6; i++) {
            bidIds[i - 1] = i;
        }

        // Claim bids
        vm.prank(address(_auctionHouse));
        (IBatchAuction.BidClaim[] memory bidClaims,) = _module.claimBids(_lotId, bidIds);

        // Total up payouts
        uint256 capacityPaidOut;
        for (uint64 i; i < 6; i++) {
            IBatchAuction.BidClaim memory bidClaim = bidClaims[i];
            capacityPaidOut += bidClaim.payout;
            if (i > 0) {
                console2.log("*****");
            }
            console2.log("paid to bid ", i + 1, "      ==>  ", bidClaim.paid);
            console2.log("payout to bid ", i + 1, "    ==>  ", bidClaim.payout);
            console2.log("refunded to bid ", i + 1, "  ==>  ", bidClaim.refund);
        }
        console2.log("capacity paid out", capacityPaidOut);

        assertEq(capacityPaidOut, _LOT_CAPACITY, "capacity");
    }
}
