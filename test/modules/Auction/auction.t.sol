// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "@forge-std-1.9.1/Test.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";

// Mocks
import {MockERC20} from "@solmate-6.8.0/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "./MockAtomicAuctionModule.sol";
import {Permit2User} from "../../lib/permit2/Permit2User.sol";

// Auctions
import {AtomicAuctionHouse} from "../../../src/AtomicAuctionHouse.sol";
import {IAuction} from "../../../src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "../../../src/interfaces/IAuctionHouse.sol";
import {ICallback} from "../../../src/interfaces/ICallback.sol";
import {IFeeManager} from "../../../src/interfaces/IFeeManager.sol";

// Modules
import {toKeycode, Module, Keycode, keycodeFromVeecode} from "../../../src/modules/Modules.sol";

contract AuctionTest is Test, Permit2User {
    MockERC20 internal _baseToken;
    MockERC20 internal _quoteToken;
    MockAtomicAuctionModule internal _mockAuctionModule;
    Keycode internal _mockAuctionModuleKeycode;

    AtomicAuctionHouse internal _auctionHouse;
    IAuctionHouse.RoutingParams internal _routingParams;
    IAuction.AuctionParams internal _auctionParams;

    address internal constant _PROTOCOL = address(0x2);
    string internal _infoHash = "";

    uint8 internal constant _QUOTE_TOKEN_DECIMALS = 18;
    uint8 internal constant _BASE_TOKEN_DECIMALS = 18;

    uint48 internal constant _REFERRER_FEE = 100;

    function setUp() external {
        // Ensure the block timestamp is a sane value
        vm.warp(1_000_000);

        _baseToken = new MockERC20("Base Token", "BASE", _BASE_TOKEN_DECIMALS);
        _quoteToken = new MockERC20("Quote Token", "QUOTE", _QUOTE_TOKEN_DECIMALS);

        _auctionHouse = new AtomicAuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _mockAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));
        _mockAuctionModuleKeycode = keycodeFromVeecode(_mockAuctionModule.VEECODE());

        _auctionHouse.installModule(_mockAuctionModule);

        _auctionHouse.setFee(_mockAuctionModuleKeycode, IFeeManager.FeeType.MaxReferrer, 1000);

        _auctionParams = IAuction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: 10e18,
            implParams: abi.encode("")
        });

        _routingParams = IAuctionHouse.RoutingParams({
            auctionType: _mockAuctionModuleKeycode,
            baseToken: address(_baseToken),
            quoteToken: address(_quoteToken),
            referrerFee: _REFERRER_FEE,
            curator: address(0),
            callbacks: ICallback(address(0)),
            callbackData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            wrapDerivative: false
        });
    }

    // [X] reverts when start time is in the past
    // [X] reverts when the duration is less than the minimum
    // [X] reverts when called by non-parent
    // [X] creates the auction lot
    // [X] creates the auction lot when start time is 0
    // [X] creates the auction lot with a custom duration
    // [X] creates the auction lot when the start time is in the future

    function testReverts_whenStartTimeIsInThePast(
        uint48 timestamp_
    ) external {
        console2.log("block.timestamp", block.timestamp);
        uint48 start = uint48(bound(timestamp_, 1, block.timestamp - 1));

        // Update auction params
        _auctionParams.start = start;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            IAuction.Auction_InvalidStart.selector, _auctionParams.start, uint48(block.timestamp)
        );
        vm.expectRevert(err);

        _auctionHouse.auction(_routingParams, _auctionParams, _infoHash);
    }

    function testReverts_whenDurationIsLessThanMinimum(
        uint48 duration_
    ) external {
        uint48 duration = uint48(bound(duration_, 0, _mockAuctionModule.minAuctionDuration() - 1));

        // Update auction params
        _auctionParams.duration = duration;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            IAuction.Auction_InvalidDuration.selector,
            _auctionParams.duration,
            _mockAuctionModule.minAuctionDuration()
        );
        vm.expectRevert(err);

        _auctionHouse.auction(_routingParams, _auctionParams, _infoHash);
    }

    function testReverts_whenCallerIsNotParent() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        _mockAuctionModule.auction(0, _auctionParams, _QUOTE_TOKEN_DECIMALS, _BASE_TOKEN_DECIMALS);
    }

    function test_success() external {
        uint96 lotId = _auctionHouse.auction(_routingParams, _auctionParams, _infoHash);

        // Get lot data from the module
        IAuction.Lot memory lot = _mockAuctionModule.getLot(lotId);
        assertEq(lot.start, uint48(block.timestamp));
        assertEq(lot.conclusion, lot.start + _auctionParams.duration);
        assertEq(lot.capacityInQuote, _auctionParams.capacityInQuote);
        assertEq(lot.capacity, _auctionParams.capacity);
        assertEq(lot.sold, 0);
        assertEq(lot.purchased, 0);
        assertEq(lot.quoteTokenDecimals, _quoteToken.decimals());
        assertEq(lot.baseTokenDecimals, _baseToken.decimals());
    }

    function test_whenStartTimeIsZero() external {
        // Update auction params
        _auctionParams.start = 0;

        uint96 lotId = _auctionHouse.auction(_routingParams, _auctionParams, _infoHash);

        // Get lot data from the module
        IAuction.Lot memory lot = _mockAuctionModule.getLot(lotId);
        assertEq(lot.start, uint48(block.timestamp)); // Sets to current timestamp
        assertEq(lot.conclusion, lot.start + _auctionParams.duration);
    }

    function test_success_withCustomDuration(
        uint48 duration_
    ) external {
        uint48 duration = uint48(bound(duration_, _mockAuctionModule.minAuctionDuration(), 1 days));

        // Update auction params
        _auctionParams.duration = duration;

        uint96 lotId = _auctionHouse.auction(_routingParams, _auctionParams, _infoHash);

        // Get lot data from the module
        IAuction.Lot memory lot = _mockAuctionModule.getLot(lotId);
        assertEq(lot.conclusion, lot.start + _auctionParams.duration);
    }

    function test_success_withFutureStartTime(
        uint48 timestamp_
    ) external {
        uint48 start = uint48(bound(timestamp_, block.timestamp + 1, block.timestamp + 1 days));

        // Update auction params
        _auctionParams.start = start;

        uint96 lotId = _auctionHouse.auction(_routingParams, _auctionParams, _infoHash);

        // Get lot data from the module
        IAuction.Lot memory lot = _mockAuctionModule.getLot(lotId);
        assertEq(lot.start, _auctionParams.start);
        assertEq(lot.conclusion, lot.start + _auctionParams.duration);
    }
}
