// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAuctionModule} from "test/modules/Auction/MockAuctionModule.sol";

// Auctions
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {IHooks, IAllowlist, Auctioneer} from "src/bases/Auctioneer.sol";

// Modules
import {
    Keycode,
    toKeycode,
    Veecode,
    wrapVeecode,
    fromVeecode,
    WithModules,
    Module
} from "src/modules/Modules.sol";

contract AuctionTest is Test {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAuctionModule internal mockAuctionModule;

    AuctionHouse internal auctionHouse;
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    function setUp() external {
        // Ensure the block timestamp is a sane value
        vm.warp(1_000_000);

        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse();
        mockAuctionModule = new MockAuctionModule(address(auctionHouse));

        auctionHouse.installModule(mockAuctionModule);

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: 10e18,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("MOCK"),
            baseToken: baseToken,
            quoteToken: quoteToken,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            payoutData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            condenserType: toKeycode("")
        });
    }

    // [X] reverts when start time is 0
    // [X] reverts when start time is in the past
    // [X] reverts when the duration is less than the minimum
    // [X] creates the auction lot
    // [X] creates the auction lot with a custom duration
    // [X] creates the auction lot when the start time is in the future

    function testReverts_whenStartTimeIsZero() external {
        // Update auction params
        auctionParams.start = 0;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Auction.Auction_InvalidStart.selector, auctionParams.start, uint48(block.timestamp)
        );
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenStartTimeIsInThePast(uint48 timestamp_) external {
        console2.log("block.timestamp", block.timestamp);
        uint48 start = uint48(bound(timestamp_, 1, block.timestamp - 1));

        // Update auction params
        auctionParams.start = start;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Auction.Auction_InvalidStart.selector, auctionParams.start, uint48(block.timestamp)
        );
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenDurationIsLessThanMinimum(uint48 duration_) external {
        uint48 duration = uint48(bound(duration_, 0, mockAuctionModule.minAuctionDuration() - 1));

        // Update auction params
        auctionParams.duration = duration;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Auction.Auction_InvalidDuration.selector,
            auctionParams.duration,
            mockAuctionModule.minAuctionDuration()
        );
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_success() external {
        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Get lot data from the module
        (
            uint48 lotStart,
            uint48 lotConclusion,
            bool lotCapacityInQuote,
            uint256 lotCapacity,
            uint256 sold,
            uint256 purchased
        ) = mockAuctionModule.lotData(lotId);

        assertEq(lotStart, uint48(block.timestamp));
        assertEq(lotConclusion, lotStart + auctionParams.duration);
        assertEq(lotCapacityInQuote, auctionParams.capacityInQuote);
        assertEq(lotCapacity, auctionParams.capacity);
        assertEq(sold, 0);
        assertEq(purchased, 0);
    }

    function test_success_withCustomDuration(uint48 duration_) external {
        uint48 duration = uint48(bound(duration_, mockAuctionModule.minAuctionDuration(), 1 days));

        // Update auction params
        auctionParams.duration = duration;

        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Get lot data from the module
        (uint48 lotStart, uint48 lotConclusion,,,,) = mockAuctionModule.lotData(lotId);
        assertEq(lotConclusion, lotStart + auctionParams.duration);
    }

    function test_success_withFutureStartTime(uint48 timestamp_) external {
        uint48 start = uint48(bound(timestamp_, block.timestamp + 1, block.timestamp + 1 days));

        // Update auction params
        auctionParams.start = start;

        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Get lot data from the module
        (uint48 lotStart, uint48 lotConclusion,,,,) = mockAuctionModule.lotData(lotId);
        assertEq(lotStart, auctionParams.start);
        assertEq(lotConclusion, lotStart + auctionParams.duration);
    }
}
