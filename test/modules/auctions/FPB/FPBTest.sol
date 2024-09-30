// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "@forge-std-1.9.1/Test.sol";
import {FixedPointMathLib as Math} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";

// Mocks
import {Permit2User} from "../../../lib/permit2/Permit2User.sol";

// Modules
import {BatchAuctionHouse} from "../../../../src/BatchAuctionHouse.sol";
import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {IBatchAuction} from "../../../../src/interfaces/modules/IBatchAuction.sol";
import {FixedPriceBatch} from "../../../../src/modules/auctions/batch/FPB.sol";
import {IFixedPriceBatch} from "../../../../src/interfaces/modules/auctions/IFixedPriceBatch.sol";

abstract contract FpbTest is Test, Permit2User {
    uint256 internal constant _BASE_SCALE = 1e18;

    address internal constant _PROTOCOL = address(0x2);
    address internal constant _BIDDER = address(0x3);
    address internal constant _REFERRER = address(0x4);

    uint256 internal constant _LOT_CAPACITY = 10e18;
    uint48 internal constant _DURATION = 1 days;
    uint24 internal constant _MIN_FILL_PERCENT = 50e2; // 50%
    uint256 internal constant _PRICE = 2e18;

    BatchAuctionHouse internal _auctionHouse;
    FixedPriceBatch internal _module;

    // Input parameters (modified by modifiers)
    uint48 internal _start;
    uint96 internal _lotId = type(uint96).max;
    IAuction.AuctionParams internal _auctionParams;
    FixedPriceBatch.AuctionDataParams internal _fpbParams;

    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;

    function setUp() external {
        vm.warp(1_000_000);

        _auctionHouse = new BatchAuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _module = new FixedPriceBatch(address(_auctionHouse));

        _start = uint48(block.timestamp) + 1;

        _fpbParams =
            IFixedPriceBatch.AuctionDataParams({price: _PRICE, minFillPercent: _MIN_FILL_PERCENT});

        _auctionParams = IAuction.AuctionParams({
            start: _start,
            duration: _DURATION,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode(_fpbParams)
        });
    }

    // ========== MODIFIERS ========== //

    function _setQuoteTokenDecimals(
        uint8 decimals_
    ) internal {
        _quoteTokenDecimals = decimals_;

        _fpbParams.price = _scaleQuoteTokenAmount(_PRICE);

        _auctionParams.implParams = abi.encode(_fpbParams);

        if (_auctionParams.capacityInQuote) {
            _auctionParams.capacity = _scaleQuoteTokenAmount(_LOT_CAPACITY);
        }
    }

    modifier givenQuoteTokenDecimals(
        uint8 decimals_
    ) {
        _setQuoteTokenDecimals(decimals_);
        _;
    }

    function _setBaseTokenDecimals(
        uint8 decimals_
    ) internal {
        _baseTokenDecimals = decimals_;

        if (!_auctionParams.capacityInQuote) {
            _auctionParams.capacity = _scaleBaseTokenAmount(_LOT_CAPACITY);
        }
    }

    modifier givenBaseTokenDecimals(
        uint8 decimals_
    ) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    function _setCapacity(
        uint256 capacity_
    ) internal {
        _auctionParams.capacity = capacity_;
    }

    modifier givenLotCapacity(
        uint256 capacity_
    ) {
        _setCapacity(capacity_);
        _;
    }

    modifier givenStartTimestamp(
        uint48 start_
    ) {
        _auctionParams.start = start_;
        _;
    }

    modifier givenDuration(
        uint48 duration_
    ) {
        _auctionParams.duration = duration_;
        _;
    }

    function _createAuctionLot() internal {
        vm.prank(address(_auctionHouse));
        _module.auction(_lotId, _auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
    }

    modifier givenLotIsCreated() {
        _createAuctionLot();
        _;
    }

    function _setPrice(
        uint256 price_
    ) internal {
        _fpbParams.price = price_;
        _auctionParams.implParams = abi.encode(_fpbParams);
    }

    modifier givenPrice(
        uint256 price_
    ) {
        _setPrice(price_);
        _;
    }

    function _setMinFillPercent(
        uint24 minFillPercent_
    ) internal {
        _fpbParams.minFillPercent = minFillPercent_;
        _auctionParams.implParams = abi.encode(_fpbParams);
    }

    modifier givenMinFillPercent(
        uint24 minFillPercent_
    ) {
        _setMinFillPercent(minFillPercent_);
        _;
    }

    function _concludeLot() internal {
        vm.warp(_start + _DURATION + 1);
    }

    modifier givenLotHasConcluded() {
        _concludeLot();
        _;
    }

    function _startLot() internal {
        vm.warp(_start + 1);
    }

    modifier givenLotHasStarted() {
        _startLot();
        _;
    }

    function _cancelAuctionLot() internal {
        vm.prank(address(_auctionHouse));
        _module.cancelAuction(_lotId);
    }

    modifier givenLotIsCancelled() {
        _cancelAuctionLot();
        _;
    }

    function _createBid(
        uint256 amount_
    ) internal {
        vm.prank(address(_auctionHouse));
        _module.bid(_lotId, _BIDDER, _REFERRER, amount_, abi.encode(""));
    }

    modifier givenBidIsCreated(
        uint256 amount_
    ) {
        _createBid(amount_);
        _;
    }

    modifier givenLotIsAborted() {
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
        _;
    }

    function _settleLot() internal {
        vm.prank(address(_auctionHouse));
        _module.settle(_lotId, 100_000);
    }

    modifier givenLotIsSettled() {
        _settleLot();
        _;
    }

    function _warpAfterSettlePeriod() internal {
        vm.warp(_start + _DURATION + _module.dedicatedSettlePeriod());
    }

    modifier givenLotSettlePeriodHasPassed() {
        _warpAfterSettlePeriod();
        _;
    }

    modifier givenDuringLotSettlePeriod() {
        vm.warp(_start + _DURATION + _module.dedicatedSettlePeriod() - 1);
        _;
    }

    function _refundBid(
        uint64 bidId_
    ) internal returns (uint256 refundAmount) {
        vm.prank(address(_auctionHouse));
        return _module.refundBid(_lotId, bidId_, 0, _BIDDER);
    }

    modifier givenBidIsRefunded(
        uint64 bidId_
    ) {
        _refundBid(bidId_);
        _;
    }

    function _claimBid(
        uint64 bidId_
    ) internal returns (IBatchAuction.BidClaim[] memory bidClaims, bytes memory auctionOutput) {
        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId_;

        vm.prank(address(_auctionHouse));
        return _module.claimBids(_lotId, bidIds);
    }

    modifier givenBidIsClaimed(
        uint64 bidId_
    ) {
        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId_;

        vm.prank(address(_auctionHouse));
        _module.claimBids(_lotId, bidIds);
        _;
    }

    // ======== Internal Functions ======== //

    function _scaleQuoteTokenAmount(
        uint256 amount_
    ) internal view returns (uint256) {
        return Math.mulDivDown(amount_, 10 ** _quoteTokenDecimals, _BASE_SCALE);
    }

    function _scaleBaseTokenAmount(
        uint256 amount_
    ) internal view returns (uint256) {
        return Math.mulDivDown(amount_, 10 ** _baseTokenDecimals, _BASE_SCALE);
    }
}
