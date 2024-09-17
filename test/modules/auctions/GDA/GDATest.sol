// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "@forge-std-1.9.1/Test.sol";
import {UD60x18, ud, uUNIT, ZERO} from "../../../../lib/prb-math/src/UD60x18.sol";
import "../../../../lib/prb-math/src/Common.sol" as PRBMath;

// Mocks
import {Permit2User} from "../../../lib/permit2/Permit2User.sol";

// Modules
import {AtomicAuctionHouse} from "../../../../src/AtomicAuctionHouse.sol";
import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {IGradualDutchAuction} from
    "../../../../src/interfaces/modules/auctions/IGradualDutchAuction.sol";
import {GradualDutchAuction} from "../../../../src/modules/auctions/atomic/GDA.sol";

abstract contract GdaTest is Test, Permit2User {
    using {PRBMath.mulDiv} for uint256;

    uint256 internal constant _BASE_SCALE = 1e18;

    address internal constant _PROTOCOL = address(0x2);
    address internal constant _BIDDER = address(0x3);
    address internal constant _REFERRER = address(0x4);

    uint256 internal constant _LOT_CAPACITY = 10e18;
    uint48 internal constant _DURATION = 2 days;
    uint256 internal constant _INITIAL_PRICE = 5e18;
    uint256 internal constant _MIN_PRICE = 25e17;
    uint256 internal constant _DECAY_TARGET = 10e16; // 10%
    uint256 internal constant _DECAY_PERIOD = 12 hours;
    UD60x18 internal constant _ONE_DAY = UD60x18.wrap(1 days * uUNIT);
    UD60x18 internal constant LN_OF_PRODUCT_LN_MAX = UD60x18.wrap(4_883_440_042_183_455_484);

    AtomicAuctionHouse internal _auctionHouse;
    GradualDutchAuction internal _module;

    // Input parameters (modified by modifiers)
    uint48 internal _start;
    uint96 internal _lotId = type(uint96).max;
    IAuction.AuctionParams internal _auctionParams;
    GradualDutchAuction.GDAParams internal _gdaParams;

    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;

    function setUp() external {
        vm.warp(1_000_000);

        _auctionHouse = new AtomicAuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _module = new GradualDutchAuction(address(_auctionHouse));

        _start = uint48(block.timestamp) + 1;

        _gdaParams = IGradualDutchAuction.GDAParams({
            equilibriumPrice: _INITIAL_PRICE,
            minimumPrice: _MIN_PRICE,
            decayTarget: _DECAY_TARGET,
            decayPeriod: _DECAY_PERIOD
        });

        _auctionParams = IAuction.AuctionParams({
            start: _start,
            duration: _DURATION,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode(_gdaParams)
        });
    }

    // ========== MODIFIERS ========== //

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteTokenDecimals = decimals_;

        _gdaParams.equilibriumPrice = _scaleQuoteTokenAmount(_INITIAL_PRICE);
        _gdaParams.minimumPrice = _scaleQuoteTokenAmount(_MIN_PRICE);

        _auctionParams.implParams = abi.encode(_gdaParams);
    }

    modifier givenQuoteTokenDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
        _;
    }

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseTokenDecimals = decimals_;

        _auctionParams.capacity = _scaleBaseTokenAmount(_LOT_CAPACITY);
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

    modifier givenEquilibriumPrice(uint128 price_) {
        _gdaParams.equilibriumPrice = uint256(price_);
        _auctionParams.implParams = abi.encode(_gdaParams);
        _;
    }

    modifier givenMinPrice(uint128 minPrice_) {
        _gdaParams.minimumPrice = uint256(minPrice_);
        _auctionParams.implParams = abi.encode(_gdaParams);
        _;
    }

    modifier givenMinIsHalfPrice(uint128 price_) {
        _gdaParams.minimumPrice = (uint256(price_) / 2) + (price_ % 2 == 0 ? 0 : 1);
        _auctionParams.implParams = abi.encode(_gdaParams);
        _;
    }

    modifier validateCapacity() {
        vm.assume(
            _auctionParams.capacity
                >= 10 ** ((_baseTokenDecimals / 2) + (_baseTokenDecimals % 2 == 0 ? 0 : 1))
        );
        _;
    }

    modifier validatePrice() {
        vm.assume(
            _gdaParams.equilibriumPrice
                >= 10 ** ((_quoteTokenDecimals / 2) + (_quoteTokenDecimals % 2 == 0 ? 0 : 1))
        );
        _;
    }

    modifier validateMinPrice() {
        vm.assume(
            _gdaParams.minimumPrice >= _gdaParams.equilibriumPrice / 2
                && _gdaParams.minimumPrice
                    <= _gdaParams.equilibriumPrice.mulDiv(uUNIT - (_gdaParams.decayTarget + 10e16), uUNIT)
        );
        _;
    }

    modifier validatePriceTimesEmissionsRate() {
        UD60x18 r = ud(
            _auctionParams.capacity.mulDiv(uUNIT, 10 ** _baseTokenDecimals).mulDiv(
                1 days, _auctionParams.duration
            )
        );

        if (_gdaParams.minimumPrice == 0) {
            UD60x18 q0 = ud(_gdaParams.equilibriumPrice.mulDiv(uUNIT, 10 ** _quoteTokenDecimals));
            vm.assume(q0.mul(r) > ZERO);
        } else {
            UD60x18 qm = ud(_gdaParams.minimumPrice.mulDiv(uUNIT, 10 ** _quoteTokenDecimals));
            vm.assume(qm.mul(r) > ZERO);
        }
        _;
    }

    modifier givenDecayTarget(uint256 decayTarget_) {
        _gdaParams.decayTarget = decayTarget_;
        _auctionParams.implParams = abi.encode(_gdaParams);
        _;
    }

    modifier givenDecayPeriod(uint256 decayPeriod_) {
        _gdaParams.decayPeriod = decayPeriod_;
        _auctionParams.implParams = abi.encode(_gdaParams);
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
        vm.warp(_start);
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
        return amount_.mulDiv(10 ** _quoteTokenDecimals, _BASE_SCALE);
    }

    function _scaleBaseTokenAmount(uint256 amount_) internal view returns (uint256) {
        return amount_.mulDiv(10 ** _baseTokenDecimals, _BASE_SCALE);
    }

    function _getAuctionLot(uint96 lotId_) internal view returns (IAuction.Lot memory) {
        return _module.getLot(lotId_);
    }

    function _getAuctionData(
        uint96 lotId_
    ) internal view returns (IGradualDutchAuction.AuctionData memory) {
        (
            uint256 eqPrice,
            uint256 minPrice,
            uint256 lastAuctionStart,
            UD60x18 decayConstant,
            UD60x18 emissionsRate
        ) = _module.auctionData(lotId_);

        return IGradualDutchAuction.AuctionData({
            equilibriumPrice: eqPrice,
            minimumPrice: minPrice,
            lastAuctionStart: lastAuctionStart,
            decayConstant: decayConstant,
            emissionsRate: emissionsRate
        });
    }
}
