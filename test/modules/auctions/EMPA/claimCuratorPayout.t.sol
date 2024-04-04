// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaClaimCuratorPayoutTest is EmpaModuleTest {
    uint96 internal constant _BID_PRICE_TWO_AMOUNT = 2e18;
    uint96 internal constant _BID_PRICE_TWO_AMOUNT_OUT = 1e18;

    uint256 internal _expectedSold;

    // ============ Modifiers ============ //

    modifier givenBidsAreAboveMinimumAndBelowCapacity() {
        // Capacity: 1 + 1 + 1 + 1 >= 2.5 minimum && < 10 capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );

        // Marginal price: 1 (due to capacity not being reached and minimum price being 1)

        // Output
        // Bid one: 2 / 1 = 2 out
        // Bid two: 2 / 1 = 2 out
        // Bid three: 2 / 1 = 2 out
        // Bid four: 2 / 1 = 2 out

        uint96 bidAmountInTotal = _scaleQuoteTokenAmount(
            _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT
                + _BID_PRICE_TWO_AMOUNT
        );
        uint96 bidAmountOutTotal = _scaleBaseTokenAmount(
            _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT
                + _BID_PRICE_TWO_AMOUNT
        );

        _expectedSold = bidAmountOutTotal;

        // No partial fill
        _;
    }

    // ============ Tests ============ //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction has not concluded
    //  [X] it reverts
    // [X] when the auction has not been settled
    //  [X] it reverts
    // [X] when the auction has been cancelled
    //  [X] it returns 0 sold
    // [X] when the curator payout has been claimed
    //  [X] it reverts
    // [X] it returns the sold amount, and updates the curator payout status

    function test_whenLotIdIsInvalid_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        vm.prank(address(_auctionHouse));
        _module.claimCuratorPayout(_lotId);
    }

    function test_givenLotConcluded_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimCuratorPayout(_lotId);
    }

    function test_givenLotNotSettled_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimCuratorPayout(_lotId);
    }

    function test_givenLotCancelled() external givenLotIsCreated givenLotIsCancelled {
        // Call function
        vm.prank(address(_auctionHouse));
        (uint256 sold) = _module.claimCuratorPayout(_lotId);

        // Assert values
        assertEq(sold, 0);

        // Assert curator payout status
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.curatorPayoutClaimed, true);
    }

    function test_givenLotCuratorPayoutClaimed_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
        givenLotCuratorPayoutIsClaimed
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimCuratorPayout(_lotId);
    }

    function test_givenLotIsUnderCapacity()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreAboveMinimumAndBelowCapacity
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call function
        vm.prank(address(_auctionHouse));
        (uint256 sold) = _module.claimCuratorPayout(_lotId);

        // Assert values
        assertEq(sold, _expectedSold);

        // Assert curator payout status
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.curatorPayoutClaimed, true);
    }
}
