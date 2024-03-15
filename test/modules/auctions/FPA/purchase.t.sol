// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {FixedPriceAuctionModule} from "src/modules/auctions/FPAM.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {FpaModuleTest} from "test/modules/auctions/FPA/FPAModuleTest.sol";

contract FpaModulePurchaseTest is FpaModuleTest {
    uint96 internal constant _PURCHASE_AMOUNT = 2e18;
    uint96 internal constant _PURCHASE_AMOUNT_OUT = 1e18;

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction has concluded
    //  [X] it reverts
    // [X] when the auction has been cancelled
    //  [X] it reverts
    // [X] when the auction has not started
    //  [X] it reverts
    // [X] when there is insufficient capacity
    //  [X] it reverts
    // [X] when capacity in quote and there is insufficient capacity
    //  [X] it reverts
    // [X] when the payout is greater than the maximum payout
    //  [X] it reverts
    // [X] when the payout is less than the minimum amount out
    //  [X] it reverts
    // [X] when the token decimals are different
    //  [X] it handles the purchase correctly
    // [X] it updates the capacity, purchased and sold

    function test_notParent_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.purchase(_lotId, _PURCHASE_AMOUNT, abi.encode(_PURCHASE_AMOUNT_OUT));
    }

    function test_invalidLotId_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT_OUT);
    }

    function test_auctionConcluded_reverts() public givenLotIsCreated givenLotHasConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT_OUT);
    }

    function test_auctionCancelled_reverts() public givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT_OUT);
    }

    function test_auctionNotStarted_reverts() public givenLotIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT_OUT);
    }

    function test_whenCapacityIsInsufficient_reverts()
        public
        givenLotCapacity(2e18)
        givenMaxPayout(1e5)
        givenLotIsCreated
        givenLotHasStarted
        givenPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT_OUT) // Payout 1, remaining capacity is 2 - 1 = 1
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InsufficientCapacity.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_PURCHASE_AMOUNT * 2, _PURCHASE_AMOUNT_OUT * 2);
    }

    function test_whenCapacityIsInsufficient_givenCapacityInQuote_reverts()
        public
        givenCapacityInQuote
        givenLotCapacity(3e18)
        givenMaxPayout(1e5)
        givenLotIsCreated
        givenLotHasStarted
        givenPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT_OUT) // Payout 1, remaining capacity is 3 - 2 = 1
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InsufficientCapacity.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT_OUT);
    }

    function test_whenPayoutIsGreaterThanMaxPayout_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(FixedPriceAuctionModule.Auction_PayoutGreaterThanMax.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(12e18, 1e18); // 12 / 2 = 6 > 5
    }

    function test_whenPayoutIsGreaterThanMaxPayout_quoteTokenDecimalsLarger_reverts()
        public
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(FixedPriceAuctionModule.Auction_PayoutGreaterThanMax.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_scaleQuoteTokenAmount(12e18), _scaleBaseTokenAmount(1e18)); // 12 / 2 = 6 > 5
    }

    function test_whenPayoutIsGreaterThanMaxPayout_quoteTokenDecimalsSmaller_reverts()
        public
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(FixedPriceAuctionModule.Auction_PayoutGreaterThanMax.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_scaleQuoteTokenAmount(12e18), _scaleBaseTokenAmount(1e18)); // 12 / 2 = 6 > 5
    }

    function test_whenPayoutIsLessThanMinAmountOut_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(FixedPriceAuctionModule.Auction_InsufficientPayout.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_scaleQuoteTokenAmount(2e18), _scaleBaseTokenAmount(3e18));
    }

    function test_whenPayoutIsLessThanMinAmountOut_quoteTokenDecimalsLarger_reverts()
        public
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(FixedPriceAuctionModule.Auction_InsufficientPayout.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_scaleQuoteTokenAmount(2e18), _scaleBaseTokenAmount(3e18));
    }

    function test_whenPayoutIsLessThanMinAmountOut_quoteTokenDecimalsSmaller_reverts()
        public
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(FixedPriceAuctionModule.Auction_InsufficientPayout.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_scaleQuoteTokenAmount(2e18), _scaleBaseTokenAmount(3e18));
    }

    function test_success() public givenLotIsCreated givenLotHasStarted {
        // Calculate expected values
        uint96 expectedSold = _mulDivDown(
            _scaleQuoteTokenAmount(_PURCHASE_AMOUNT),
            uint96(10) ** _baseTokenDecimals,
            _scaleQuoteTokenAmount(_PRICE)
        );

        // Call the function
        _createPurchase(
            _scaleQuoteTokenAmount(_PURCHASE_AMOUNT), _scaleBaseTokenAmount(_PURCHASE_AMOUNT_OUT)
        );

        // Assert the capacity, purchased and sold
        Auction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedSold, "capacity");
        assertEq(lot.purchased, _scaleQuoteTokenAmount(_PURCHASE_AMOUNT), "purchased");
        assertEq(lot.sold, expectedSold, "sold");
    }

    function test_success_quoteTokenDecimalsLarger()
        public
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Calculate expected values
        uint96 expectedSold = _mulDivDown(
            _scaleQuoteTokenAmount(_PURCHASE_AMOUNT),
            uint96(10) ** _baseTokenDecimals,
            _scaleQuoteTokenAmount(_PRICE)
        );

        // Call the function
        _createPurchase(
            _scaleQuoteTokenAmount(_PURCHASE_AMOUNT), _scaleBaseTokenAmount(_PURCHASE_AMOUNT_OUT)
        );

        // Assert the capacity, purchased and sold
        Auction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedSold, "capacity");
        assertEq(lot.purchased, _scaleQuoteTokenAmount(_PURCHASE_AMOUNT), "purchased");
        assertEq(lot.sold, expectedSold, "sold");
    }

    function test_success_quoteTokenDecimalsSmaller()
        public
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Calculate expected values
        uint96 expectedSold = _mulDivDown(
            _scaleQuoteTokenAmount(_PURCHASE_AMOUNT),
            uint96(10) ** _baseTokenDecimals,
            _scaleQuoteTokenAmount(_PRICE)
        );

        // Call the function
        _createPurchase(
            _scaleQuoteTokenAmount(_PURCHASE_AMOUNT), _scaleBaseTokenAmount(_PURCHASE_AMOUNT_OUT)
        );

        // Assert the capacity, purchased and sold
        Auction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedSold, "capacity");
        assertEq(lot.purchased, _scaleQuoteTokenAmount(_PURCHASE_AMOUNT), "purchased");
        assertEq(lot.sold, expectedSold, "sold");
    }

    function test_success_givenCapacityInQuote()
        public
        givenCapacityInQuote
        givenLotIsCreated
        givenLotHasStarted
    {
        // Calculate expected values
        uint96 expectedSold = _mulDivDown(
            _scaleQuoteTokenAmount(_PURCHASE_AMOUNT),
            uint96(10) ** _baseTokenDecimals,
            _scaleQuoteTokenAmount(_PRICE)
        );

        // Call the function
        _createPurchase(
            _scaleQuoteTokenAmount(_PURCHASE_AMOUNT), _scaleBaseTokenAmount(_PURCHASE_AMOUNT_OUT)
        );

        // Assert the capacity, purchased and sold
        Auction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(
            lot.capacity,
            _scaleBaseTokenAmount(_LOT_CAPACITY) - _scaleQuoteTokenAmount(_PURCHASE_AMOUNT),
            "capacity"
        );
        assertEq(lot.purchased, _scaleQuoteTokenAmount(_PURCHASE_AMOUNT), "purchased");
        assertEq(lot.sold, expectedSold, "sold");
    }
}
