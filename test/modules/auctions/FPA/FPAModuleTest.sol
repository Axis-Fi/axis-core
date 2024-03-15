// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

// Mocks
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Modules
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {FixedPriceAuctionModule} from "src/modules/auctions/FPAM.sol";

abstract contract FpaModuleTest is Test, Permit2User {
    uint96 internal constant _BASE_SCALE = 1e18;

    address internal constant _PROTOCOL = address(0x2);
    address internal constant _BIDDER = address(0x3);
    address internal constant _REFERRER = address(0x4);

    uint96 internal constant _LOT_CAPACITY = 10e18;
    uint48 internal constant _DURATION = 1 days;
    uint24 internal constant _MAX_PAYOUT_PERCENT = 5e4; // 50%
    uint96 internal constant _PRICE = 2e18;

    AuctionHouse internal _auctionHouse;
    FixedPriceAuctionModule internal _module;

    // Input parameters (modified by modifiers)
    uint48 internal _start;
    uint96 internal _lotId = type(uint96).max;
    Auction.AuctionParams internal _auctionParams;
    FixedPriceAuctionModule.FixedPriceParams internal _fpaParams;

    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;

    function setUp() external {
        vm.warp(1_000_000);

        _auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _module = new FixedPriceAuctionModule(address(_auctionHouse));

        _start = uint48(block.timestamp) + 1;

        _fpaParams = FixedPriceAuctionModule.FixedPriceParams({
            price: _PRICE,
            maxPayoutPercent: _MAX_PAYOUT_PERCENT
        });

        _auctionParams = Auction.AuctionParams({
            start: _start,
            duration: _DURATION,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode(_fpaParams)
        });
    }

    // ========== MODIFIERS ========== //

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteTokenDecimals = decimals_;

        _fpaParams.price = _scaleQuoteTokenAmount(_PRICE);

        _auctionParams.implParams = abi.encode(_fpaParams);

        if (_auctionParams.capacityInQuote) {
            _auctionParams.capacity = _scaleQuoteTokenAmount(_LOT_CAPACITY);
        }
    }

    modifier givenQuoteTokenDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
        _;
    }

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseTokenDecimals = decimals_;

        if (!_auctionParams.capacityInQuote) {
            _auctionParams.capacity = _scaleBaseTokenAmount(_LOT_CAPACITY);
        }
    }

    modifier givenBaseTokenDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    modifier givenLotCapacity(uint96 capacity_) {
        _auctionParams.capacity = capacity_;
        _;
    }

    modifier givenStartTimestamp(uint48 start_) {
        _auctionParams.start = start_;
        _;
    }

    modifier givenDuration(uint48 duration_) {
        _auctionParams.duration = duration_;
        _;
    }

    modifier givenCapacityInQuote() {
        _auctionParams.capacityInQuote = true;
        _;
    }

    function _createAuctionLot() internal returns (uint256 capacity) {
        vm.prank(address(_auctionHouse));
        return _module.auction(_lotId, _auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
    }

    modifier givenLotIsCreated() {
        _createAuctionLot();
        _;
    }

    modifier givenPrice(uint96 price_) {
        _fpaParams.price = price_;
        _auctionParams.implParams = abi.encode(_fpaParams);
        _;
    }

    function setMaxPayout(uint24 maxPayout_) internal {
        _fpaParams.maxPayoutPercent = maxPayout_;
        _auctionParams.implParams = abi.encode(_fpaParams);
    }

    modifier givenMaxPayout(uint24 maxPayout_) {
        setMaxPayout(maxPayout_);
        _;
    }

    function _concludeLot() internal {
        vm.warp(_start + _DURATION + 1);
    }

    modifier givenLotHasConcluded() {
        _concludeLot();
        _;
    }

    modifier givenLotHasStarted() {
        vm.warp(_start + 1);
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

    function _createPurchase(uint96 amount_, uint96 minAmountOut_) internal {
        vm.prank(address(_auctionHouse));
        _module.purchase(_lotId, amount_, abi.encode(minAmountOut_));
    }

    modifier givenPurchase(uint96 amount_, uint96 minAmountOut_) {
        _createPurchase(amount_, minAmountOut_);
        _;
    }

    // ======== Internal Functions ======== //

    function _mulDivUp(uint96 mul1_, uint96 mul2_, uint96 div_) internal pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivUp(mul1_, mul2_, div_);
        if (product > type(uint96).max) revert("overflow");

        return uint96(product);
    }

    function _mulDivDown(uint96 mul1_, uint96 mul2_, uint96 div_) internal pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivDown(mul1_, mul2_, div_);
        if (product > type(uint96).max) revert("overflow");

        return uint96(product);
    }

    function _scaleQuoteTokenAmount(uint96 amount_) internal view returns (uint96) {
        return _mulDivUp(amount_, uint96(10 ** _quoteTokenDecimals), _BASE_SCALE);
    }

    function _scaleBaseTokenAmount(uint96 amount_) internal view returns (uint96) {
        return _mulDivUp(amount_, uint96(10 ** _baseTokenDecimals), _BASE_SCALE);
    }

    function _getAuctionLot(uint96 lotId_) internal view returns (Auction.Lot memory) {
        return _module.getLot(lotId_);
    }

    function _getAuctionData(uint96 lotId_)
        internal
        view
        returns (FixedPriceAuctionModule.AuctionData memory)
    {
        (uint96 price_, uint96 maxPayout_) = _module.auctionData(lotId_);

        return FixedPriceAuctionModule.AuctionData({price: price_, maxPayout: maxPayout_});
    }
}
