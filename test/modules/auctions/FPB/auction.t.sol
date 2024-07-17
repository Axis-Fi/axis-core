// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPointMathLib as Math} from "@solady-0.0.124/utils/FixedPointMathLib.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbCreateAuctionTest is FpbTest {
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the start time is in the past
    //  [X] it reverts
    // [X] when the duration is less than the minimum
    //  [X] it reverts
    // [X] when the price is 0
    //  [X] it reverts
    // [X] when the minimum fill percentage is > 100%
    //  [X] it reverts
    // [X] when the start time is 0
    //  [X] it sets it to the current block timestamp
    // [X] it sets the price and minFilled

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
            IAuction.Auction_InvalidStart.selector, _auctionParams.start, uint48(block.timestamp)
        );
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_durationLessThanMinimum_reverts() public givenDuration(uint48(8 hours)) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            IAuction.Auction_InvalidDuration.selector, _auctionParams.duration, uint48(1 days)
        );
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_priceIsZero_reverts() public givenPrice(0) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_minFillPercentageGreaterThan100_reverts() public givenMinFillPercent(100e2 + 1) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_startTimeIsZero_setsToCurrentBlockTimestamp() public givenStartTimestamp(0) {
        // Call the function
        _createAuctionLot();

        // Assert state
        IAuction.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.start, uint48(block.timestamp), "start");
        assertEq(
            lotData.conclusion, uint48(block.timestamp + _auctionParams.duration), "conclusion"
        );
    }

    function test_success(uint256 capacity_, uint256 price_, uint24 minFillPercent_) public {
        uint256 capacity = bound(capacity_, 1, type(uint256).max);
        _setCapacity(capacity);
        uint256 price = bound(price_, 1, type(uint256).max);
        _setPrice(price);
        uint24 minFillPercent = uint24(bound(minFillPercent_, 0, 100e2));
        _setMinFillPercent(minFillPercent);

        // Call the function
        _createAuctionLot();

        // Round up to be conservative
        uint256 minFilled = Math.fullMulDivUp(capacity, minFillPercent, 100e2);

        // Assert state
        IAuction.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.capacity, capacity, "capacity");
        assertEq(lotData.capacityInQuote, false, "capacityInQuote");
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.start, _auctionParams.start, "start");
        assertEq(lotData.conclusion, _auctionParams.start + _auctionParams.duration, "conclusion");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(auctionData.price, price, "price");
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Created), "status");
        assertEq(auctionData.nextBidId, 1, "nextBidId");
        assertEq(auctionData.settlementCleared, false, "settlementCleared");
        assertEq(auctionData.totalBidAmount, 0, "totalBidAmount");
        assertEq(auctionData.minFilled, minFilled, "minFilled");
    }
}
