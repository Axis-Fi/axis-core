// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib as Math} from "lib/solmate/src/utils/FixedPointMathLib.sol";

// Mocks
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Modules
import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {IAuctionModule} from "src/interfaces/IAuctionModule.sol";
import {FixedPriceSale} from "src/modules/auctions/FPS.sol";

abstract contract FpsTest is Test, Permit2User {
    uint256 internal constant _BASE_SCALE = 1e18;

    address internal constant _PROTOCOL = address(0x2);
    address internal constant _BIDDER = address(0x3);
    address internal constant _REFERRER = address(0x4);

    uint256 internal constant _LOT_CAPACITY = 10e18;
    uint48 internal constant _DURATION = 1 days;
    uint24 internal constant _MAX_PAYOUT_PERCENT = 5e4; // 50%
    uint256 internal constant _PRICE = 2e18;

    AtomicAuctionHouse internal _auctionHouse;
    FixedPriceSale internal _module;

    // Input parameters (modified by modifiers)
    uint48 internal _start;
    uint96 internal _lotId = type(uint96).max;
    IAuctionModule.AuctionParams internal _auctionParams;
    FixedPriceSale.FixedPriceParams internal _fpaParams;

    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;

    function setUp() external {
        vm.warp(1_000_000);

        _auctionHouse = new AtomicAuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _module = new FixedPriceSale(address(_auctionHouse));

        _start = uint48(block.timestamp) + 1;

        _fpaParams =
            FixedPriceSale.FixedPriceParams({price: _PRICE, maxPayoutPercent: _MAX_PAYOUT_PERCENT});

        _auctionParams = IAuctionModule.AuctionParams({
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

    modifier givenLotCapacity(uint256 capacity_) {
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

    function _createAuctionLot() internal {
        vm.prank(address(_auctionHouse));
        _module.auction(_lotId, _auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
    }

    modifier givenLotIsCreated() {
        _createAuctionLot();
        _;
    }

    modifier givenPrice(uint256 price_) {
        _fpaParams.price = price_;
        _auctionParams.implParams = abi.encode(_fpaParams);
        _;
    }

    function _setMaxPayout(uint24 maxPayout_) internal {
        _fpaParams.maxPayoutPercent = maxPayout_;
        _auctionParams.implParams = abi.encode(_fpaParams);
    }

    modifier givenMaxPayout(uint24 maxPayout_) {
        _setMaxPayout(maxPayout_);
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

    function _createPurchase(uint256 amount_, uint256 minAmountOut_) internal {
        vm.prank(address(_auctionHouse));
        _module.purchase(_lotId, amount_, abi.encode(minAmountOut_));
    }

    modifier givenPurchase(uint256 amount_, uint256 minAmountOut_) {
        _createPurchase(amount_, minAmountOut_);
        _;
    }

    // ======== Internal Functions ======== //

    function _scaleQuoteTokenAmount(uint256 amount_) internal view returns (uint256) {
        return Math.mulDivDown(amount_, 10 ** _quoteTokenDecimals, _BASE_SCALE);
    }

    function _scaleBaseTokenAmount(uint256 amount_) internal view returns (uint256) {
        return Math.mulDivDown(amount_, 10 ** _baseTokenDecimals, _BASE_SCALE);
    }

    function _getAuctionLot(uint96 lotId_) internal view returns (IAuctionModule.Lot memory) {
        return _module.getLot(lotId_);
    }

    function _getAuctionData(uint96 lotId_)
        internal
        view
        returns (FixedPriceSale.AuctionData memory)
    {
        (uint256 price_, uint256 maxPayout_) = _module.auctionData(lotId_);

        return FixedPriceSale.AuctionData({price: price_, maxPayout: maxPayout_});
    }
}
