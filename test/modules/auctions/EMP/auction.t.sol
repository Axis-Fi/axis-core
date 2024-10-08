// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "../../../../src/modules/Modules.sol";
import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {EncryptedMarginalPrice} from "../../../../src/modules/auctions/batch/EMP.sol";
import {IEncryptedMarginalPrice} from
    "../../../../src/interfaces/modules/auctions/IEncryptedMarginalPrice.sol";

import {EmpTest} from "./EMPTest.sol";

contract EmpCreateAuctionTest is EmpTest {
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the start time is in the past
    //  [X] it reverts
    // [X] when the duration is less than the minimum
    //  [X] it reverts
    // [X] when the minimum price is 0
    //  [X] it reverts
    // [X] when the minimum fill percentage is > 100%
    //  [X] it reverts
    // [X] when the minimum bid percentage is > 100%
    //  [X] it reverts
    // [X] when the minimum bid percentage is < minimum
    //  [X] it reverts
    // [X] when the auction public key is invalid
    //  [X] it reverts
    // [X] when the start time is 0
    //  [X] it sets it to the current block timestamp
    // [X] it records the auction parameters

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

    function test_minimumPriceIsZero_reverts() public givenMinimumPrice(0) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_minFillAboveMax_reverts() public givenMinimumFillPercentage(100e2 + 1) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_minBidSizeAboveMax_reverts()
        public
        givenMinimumBidSize(uint256(type(uint96).max) + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_minBidSizeZero_reverts() public givenMinimumBidSize(0) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_auctionPublicKeyIsInvalid_reverts() public givenAuctionPublicKeyIsInvalid {
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
        IAuction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.start, uint48(block.timestamp));
        assertEq(lotData.conclusion, uint48(block.timestamp + _auctionParams.duration));
    }

    function test_incorrectAuctionDataParams_reverts() public {
        _auctionParams.implParams = abi.encode("");

        // Expect revert
        vm.expectRevert();

        // Call the function
        _createAuctionLot();
    }

    function test_success() public {
        // Call the function
        _createAuctionLot();

        // Assert state
        IAuction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.start, _auctionParams.start, "start");
        assertEq(lotData.conclusion, _auctionParams.start + _auctionParams.duration, "conclusion");
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, false, "capacityInQuote");
        assertEq(lotData.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY), "capacity");
        assertEq(lotData.sold, 0, "sold");
        assertEq(lotData.purchased, 0, "purchased");

        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextBidId, 1, "nextBidId");
        assertEq(auctionData.marginalPrice, 0, "marginalPrice");
        assertEq(auctionData.minPrice, _scaleQuoteTokenAmount(_MIN_PRICE), "minPrice");
        assertEq(auctionData.nextDecryptIndex, 0, "nextDecryptIndex");
        assertEq(
            auctionData.minFilled, _scaleBaseTokenAmount(_LOT_CAPACITY) * _MIN_FILL_PERCENT / 100e2
        );
        assertEq(auctionData.minBidSize, _scaleQuoteTokenAmount(_MIN_BID_SIZE), "minBidSize");
        assertEq(
            uint8(auctionData.status), uint8(IEncryptedMarginalPrice.LotStatus.Created), "status"
        );
        assertEq(auctionData.publicKey.x, _auctionPublicKey.x);
        assertEq(auctionData.publicKey.y, _auctionPublicKey.y);
        assertEq(auctionData.privateKey, 0);
    }

    function test_success_quoteTokenDecimalsLarger()
        public
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
    {
        // Call the function
        _createAuctionLot();

        // Assert state
        IAuction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.start, _auctionParams.start, "start");
        assertEq(lotData.conclusion, _auctionParams.start + _auctionParams.duration, "conclusion");
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, false, "capacityInQuote");
        assertEq(lotData.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY), "capacity");
        assertEq(lotData.sold, 0, "sold");
        assertEq(lotData.purchased, 0, "purchased");

        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextBidId, 1, "nextBidId");
        assertEq(auctionData.marginalPrice, 0, "marginalPrice");
        assertEq(auctionData.minPrice, _scaleQuoteTokenAmount(_MIN_PRICE), "minPrice");
        assertEq(auctionData.nextDecryptIndex, 0, "nextDecryptIndex");
        assertEq(
            auctionData.minFilled, _scaleBaseTokenAmount(_LOT_CAPACITY) * _MIN_FILL_PERCENT / 100e2
        );
        assertEq(auctionData.minBidSize, _scaleQuoteTokenAmount(_MIN_BID_SIZE), "minBidSize");
        assertEq(
            uint8(auctionData.status), uint8(IEncryptedMarginalPrice.LotStatus.Created), "status"
        );
        assertEq(auctionData.publicKey.x, _auctionPublicKey.x);
        assertEq(auctionData.publicKey.y, _auctionPublicKey.y);
        assertEq(auctionData.privateKey, 0);
    }

    function test_success_quoteTokenDecimalsSmaller()
        public
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
    {
        // Call the function
        _createAuctionLot();

        // Assert state
        IAuction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.start, _auctionParams.start, "start");
        assertEq(lotData.conclusion, _auctionParams.start + _auctionParams.duration, "conclusion");
        assertEq(lotData.quoteTokenDecimals, _quoteTokenDecimals, "quoteTokenDecimals");
        assertEq(lotData.baseTokenDecimals, _baseTokenDecimals, "baseTokenDecimals");
        assertEq(lotData.capacityInQuote, false, "capacityInQuote");
        assertEq(lotData.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY), "capacity");
        assertEq(lotData.sold, 0, "sold");
        assertEq(lotData.purchased, 0, "purchased");

        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextBidId, 1, "nextBidId");
        assertEq(auctionData.marginalPrice, 0, "marginalPrice");
        assertEq(auctionData.minPrice, _scaleQuoteTokenAmount(_MIN_PRICE), "minPrice");
        assertEq(auctionData.nextDecryptIndex, 0, "nextDecryptIndex");
        assertEq(
            auctionData.minFilled, _scaleBaseTokenAmount(_LOT_CAPACITY) * _MIN_FILL_PERCENT / 100e2
        );
        assertEq(auctionData.minBidSize, _scaleQuoteTokenAmount(_MIN_BID_SIZE), "minBidSize");
        assertEq(
            uint8(auctionData.status), uint8(IEncryptedMarginalPrice.LotStatus.Created), "status"
        );
        assertEq(auctionData.publicKey.x, _auctionPublicKey.x);
        assertEq(auctionData.publicKey.y, _auctionPublicKey.y);
        assertEq(auctionData.privateKey, 0);
    }
}
