// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {FixedPriceAuctionModule} from "src/modules/auctions/FPAM.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {FpaModuleTest} from "test/modules/auctions/FPA/FPAModuleTest.sol";

contract FpaModuleAuctionTest is FpaModuleTest {
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the start time is in the past
    //  [X] it reverts
    // [X] when the duration is less than the minimum
    //  [X] it reverts
    // [X] when the fixed price is 0
    //  [X] it reverts
    // [X] when the max payout percent is < 1%
    //  [X] it reverts
    // [X] when the max payout percent is > 100%
    //  [X] it reverts
    // [X] when the token decimals differ
    //  [X] it handles the calculations correctly
    // [X] when the capacity is in quote token
    //  [X] it sets the max payout in terms of the base token
    // [X] it sets the price, max payout and lot data

    function test_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.auction(_lotId, _auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
    }

    function test_startTimeInPast_reverts()
        public
        givenStartTimestamp(uint48(block.timestamp - 1))
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Auction.Auction_InvalidStart.selector, _auctionParams.start, uint48(block.timestamp)
        );
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_durationLessThanMinimum_reverts() public givenDuration(uint48(8 hours)) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Auction.Auction_InvalidDuration.selector, _auctionParams.duration, uint48(1 days)
        );
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_fixedPriceIsZero_reverts() public givenPrice(0) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_maxPayoutPercentIsLessThanMinimum_reverts(uint24 maxPayout_) public {
        uint24 maxPayout = uint24(bound(maxPayout_, 0, 1e3 - 1));
        setMaxPayout(maxPayout);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_maxPayoutPercentIsGreaterThanMaximum_reverts(uint24 maxPayout_) public {
        uint24 maxPayout = uint24(bound(maxPayout_, 1e5 + 1, type(uint24).max));
        setMaxPayout(maxPayout);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_maxPayoutPercent_fuzz(uint24 maxPayout_) public {
        uint24 maxPayout = uint24(bound(maxPayout_, 1e3, 1e5));
        setMaxPayout(maxPayout);

        // Calculate the expected value
        uint96 expectedMaxPayout = _mulDivDown(_LOT_CAPACITY, maxPayout, 1e5);

        // Call the function
        _createAuctionLot();

        // Check the value
        FixedPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.maxPayout, expectedMaxPayout);
    }

    function test_capacityInQuote() public givenCapacityInQuote {
        // Calculate the expected value
        uint96 expectedMaxPayoutInQuote =
            _mulDivDown(_scaleQuoteTokenAmount(_LOT_CAPACITY), _fpaParams.maxPayoutPercent, 1e5);
        uint96 expectedMaxPayout = _mulDivDown(
            expectedMaxPayoutInQuote,
            uint96(10) ** _baseTokenDecimals,
            _scaleQuoteTokenAmount(_PRICE)
        );

        // Call the function
        _createAuctionLot();

        // Check the lot data
        Auction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, true, "capacityInQuote");
        assertEq(lotData.capacity, _scaleQuoteTokenAmount(_LOT_CAPACITY), "capacity");

        // Check the value
        FixedPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.maxPayout, expectedMaxPayout, "maxPayout");
    }

    function test_capacityInQuote_quoteTokenDecimalsLarger()
        public
        givenCapacityInQuote
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
    {
        // Calculate the expected value
        uint96 expectedMaxPayoutInQuote =
            _mulDivDown(_scaleQuoteTokenAmount(_LOT_CAPACITY), _fpaParams.maxPayoutPercent, 1e5);
        uint96 expectedMaxPayout = _mulDivDown(
            expectedMaxPayoutInQuote,
            uint96(10) ** _baseTokenDecimals,
            _scaleQuoteTokenAmount(_PRICE)
        );

        // Call the function
        _createAuctionLot();

        // Check the lot data
        Auction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, true, "capacityInQuote");
        assertEq(lotData.capacity, _scaleQuoteTokenAmount(_LOT_CAPACITY), "capacity");

        // Check the value
        FixedPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.maxPayout, expectedMaxPayout, "maxPayout");
    }

    function test_capacityInQuote_quoteTokenDecimalsSmaller()
        public
        givenCapacityInQuote
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
    {
        // Calculate the expected value
        uint96 expectedMaxPayoutInQuote =
            _mulDivDown(_scaleQuoteTokenAmount(_LOT_CAPACITY), _fpaParams.maxPayoutPercent, 1e5);
        uint96 expectedMaxPayout = _mulDivDown(
            expectedMaxPayoutInQuote,
            uint96(10) ** _baseTokenDecimals,
            _scaleQuoteTokenAmount(_PRICE)
        );

        // Call the function
        _createAuctionLot();

        // Check the lot data
        Auction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, true, "capacityInQuote");
        assertEq(lotData.capacity, _scaleQuoteTokenAmount(_LOT_CAPACITY), "capacity");

        // Check the value
        FixedPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.maxPayout, expectedMaxPayout, "maxPayout");
    }

    function test_success() public {
        // Call the function
        _createAuctionLot();

        // Check the lot data
        Auction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.start, _start, "start");
        assertEq(lotData.conclusion, _start + _DURATION, "conclusion");
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, false, "capacityInQuote");
        assertEq(lotData.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY), "capacity");
        assertEq(lotData.sold, 0, "sold");
        assertEq(lotData.purchased, 0, "purchased");

        // Check the auction data
        FixedPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.price, _scaleQuoteTokenAmount(_PRICE), "price");
        assertEq(
            auctionData.maxPayout,
            _mulDivDown(_scaleBaseTokenAmount(_LOT_CAPACITY), _MAX_PAYOUT_PERCENT, 1e5),
            "maxPayout"
        );
    }

    function test_success_quoteTokenDecimalsLarger()
        public
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
    {
        // Call the function
        _createAuctionLot();

        // Check the lot data
        Auction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.start, _start, "start");
        assertEq(lotData.conclusion, _start + _DURATION, "conclusion");
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, false, "capacityInQuote");
        assertEq(lotData.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY), "capacity");
        assertEq(lotData.sold, 0, "sold");
        assertEq(lotData.purchased, 0, "purchased");

        // Check the auction data
        FixedPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.price, _scaleQuoteTokenAmount(_PRICE), "price");
        assertEq(
            auctionData.maxPayout,
            _mulDivDown(_scaleBaseTokenAmount(_LOT_CAPACITY), _MAX_PAYOUT_PERCENT, 1e5),
            "maxPayout"
        );
    }

    function test_success_quoteTokenDecimalsSmaller()
        public
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
    {
        // Call the function
        _createAuctionLot();

        // Check the lot data
        Auction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.start, _start, "start");
        assertEq(lotData.conclusion, _start + _DURATION, "conclusion");
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, false, "capacityInQuote");
        assertEq(lotData.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY), "capacity");
        assertEq(lotData.sold, 0, "sold");
        assertEq(lotData.purchased, 0, "purchased");

        // Check the auction data
        FixedPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.price, _scaleQuoteTokenAmount(_PRICE), "price");
        assertEq(
            auctionData.maxPayout,
            _mulDivDown(_scaleBaseTokenAmount(_LOT_CAPACITY), _MAX_PAYOUT_PERCENT, 1e5),
            "maxPayout"
        );
    }
}
