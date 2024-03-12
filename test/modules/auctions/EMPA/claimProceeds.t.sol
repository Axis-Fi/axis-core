// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleClaimProceedsTest is EmpaModuleTest {
    uint96 internal constant _BID_PRICE_TWO_AMOUNT = 2e18;
    uint96 internal constant _BID_PRICE_TWO_AMOUNT_OUT = 1e18;
    uint96 internal constant _BID_SIZE_NINE_AMOUNT = 19e18;
    uint96 internal constant _BID_SIZE_NINE_AMOUNT_OUT = 9e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_TWO_AMOUNT = 4e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT = 2e18;

    uint256 internal _expectedSold;
    uint256 internal _expectedPurchased;
    uint256 internal _expectedPartialPayout;

    // ============ Modifiers ============ //

    modifier givenLotIsOverSubscribed() {
        // Capacity: 9 + 2 > 10 capacity
        // Capacity reached on bid 2
        _createBid(
            _scaleQuoteTokenAmount(_BID_SIZE_NINE_AMOUNT),
            _scaleBaseTokenAmount(_BID_SIZE_NINE_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );

        // Marginal price: 2 >= 1 (due to capacity being reached on bid 2)
        uint96 expectedMarginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);

        // Output
        // Bid one: 19 / 2 = 9.5 out
        // Bid two: 10 - 9.5 = 0.5 out (partial fill)

        uint96 bidOneAmountOutActual = _mulDivUp(
            _scaleQuoteTokenAmount(_BID_SIZE_NINE_AMOUNT),
            uint96(10 ** _baseTokenDecimals),
            expectedMarginalPrice
        ); // 9.5
        uint96 bidOneAmountInActual = _scaleQuoteTokenAmount(_BID_SIZE_NINE_AMOUNT); // 19
        uint96 bidTwoAmountOutActual = _auctionParams.capacity - bidOneAmountOutActual; // 0.5
        uint96 bidTwoAmountInActual = _mulDivUp(
            bidTwoAmountOutActual,
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        ); // 0.5 * 4 / 2 = 1

        uint96 bidAmountInSuccess = bidOneAmountInActual + bidTwoAmountInActual;
        uint96 bidAmountInFail =
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT) - bidTwoAmountInActual;
        uint96 bidAmountOutSuccess = bidOneAmountOutActual + bidTwoAmountOutActual;

        _expectedPurchased = bidAmountInSuccess;
        _expectedSold = bidAmountOutSuccess;
        _expectedPartialPayout = bidTwoAmountOutActual;
        _;
    }

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

        _expectedPurchased = bidAmountInTotal;
        _expectedSold = bidAmountOutTotal;

        // No partial fill
        _;
    }

    // ============ Test Cases ============ //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot is decrypted
    //  [X] it reverts
    // [X] given the auction is cancelled
    //  [X] it reverts
    // [X] given the auction is concluded
    //  [X] it reverts
    // [X] given the auction proceeds have been claimed
    //  [X] it reverts
    // [X] when the lot settlement is a partial fill
    //  [X] it updates the auction status to claimed, and returns the required information
    // [X] it updates the auction status to claimed, and returns the required information

    function test_whenLotIdIsInvalid_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        vm.prank(address(_auctionHouse));
        _module.claimProceeds(_lotId);
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
        _module.claimProceeds(_lotId);
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
        _module.claimProceeds(_lotId);
    }

    function test_givenLotCancelled_reverts() external givenLotIsCreated givenLotIsCancelled {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimProceeds(_lotId);
    }

    function test_givenLotProceedsClaimed_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
        givenLotProceedsAreClaimed
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.claimProceeds(_lotId);
    }

    function test_givenLotIsOverSubscribed()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsOverSubscribed
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call function
        vm.prank(address(_auctionHouse));
        (uint256 purchased, uint256 sold, uint256 partialPayout) = _module.claimProceeds(_lotId);

        // Assert values
        assertEq(purchased, _expectedPurchased);
        assertEq(sold, _expectedSold);
        assertEq(partialPayout, _expectedPartialPayout);
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
        (uint256 purchased, uint256 sold, uint256 partialPayout) = _module.claimProceeds(_lotId);

        // Assert values
        assertEq(purchased, _expectedPurchased);
        assertEq(sold, _expectedSold);
        assertEq(partialPayout, _expectedPartialPayout);
    }
}
