// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

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

    uint256 internal lotId;

    address internal auctionOwner = address(0x1);

    function setUp() external {
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

    modifier whenLotIsCreated() {
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    // cancel
    // [X] reverts if not the owner
    // [X] reverts if lot is not active
    // [X] reverts if lot id is invalid
    // [X] sets the lot to inactive on the AuctionModule

    function testReverts_whenAuctionHouseOwner() external whenLotIsCreated {
        bytes memory err =
            abi.encodeWithSelector(Auctioneer.HOUSE_NotAuctionOwner.selector, address(this));
        vm.expectRevert(err);

        auctionHouse.cancel(lotId);
    }

    function testReverts_whenUnauthorized(address user_) external whenLotIsCreated {
        vm.assume(user_ != auctionOwner);

        bytes memory err = abi.encodeWithSelector(Auctioneer.HOUSE_NotAuctionOwner.selector, user_);
        vm.expectRevert(err);

        vm.prank(user_);
        auctionHouse.cancel(lotId);
    }

    function testReverts_whenLotIdInvalid() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.HOUSE_InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        auctionHouse.cancel(lotId);
    }

    function testReverts_whenLotIsInactive() external whenLotIsCreated {
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);

        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);
    }

    function test_success() external whenLotIsCreated {
        assertTrue(mockAuctionModule.isLive(lotId), "before cancellation: isLive mismatch");

        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);

        // Get lot data from the module
        (, uint48 lotConclusion,, uint256 lotCapacity,,) = mockAuctionModule.lotData(lotId);
        assertEq(lotConclusion, uint48(block.timestamp));
        assertEq(lotCapacity, 0);

        assertFalse(mockAuctionModule.isLive(lotId), "after cancellation: isLive mismatch");
    }
}
