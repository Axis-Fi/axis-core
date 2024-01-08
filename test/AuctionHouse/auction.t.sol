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
import {Keycode, toKeycode, fromKeycode, WithModules} from "src/modules/Modules.sol";

contract AuctionTest is Test {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAuctionModule internal mockModule;

    AuctionHouse internal auctionHouse;
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse();
        mockModule = new MockAuctionModule(address(auctionHouse));

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

    modifier whenAuctionModuleIsInstalled() {
        auctionHouse.installModule(mockModule);
        _;
    }

    // auction
    // [X] reverts when auction module is sunset
    // [X] reverts when auction module is not installed
    // [ ] reverts when base token decimals are out of bounds
    // [ ] reverts when quote token decimals are out of bounds
    // [ ] reverts when duration is 0
    // [ ] reverts when capacity is 0
    // [ ] stores the auction lot
    // [ ] uses the auction module version after a new version is installed
    // [ ] derivatives
    //  [ ] reverts when derivative type is sunset
    //  [ ] reverts when derivative type is not installed
    //  [ ] reverts when derivation validation fails
    //  [ ] sets the derivative on the auction lot
    // [ ] allowlist
    //  [ ] reverts when allowlist validation fails
    //  [ ] sets the allowlist on the auction lot
    // [ ] condenser
    //  [ ] reverts when condenser type is sunset
    //  [ ] reverts when condenser type is not installed
    //  [ ] sets the condenser on the auction lot
    // [ ] hooks
    //  [ ] sets the hooks on the auction lot

    function testReverts_whenModuleNotInstalled() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 0);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenModuleIsSunset() external whenAuctionModuleIsInstalled {
        // Sunset the module, which prevents the creation of new auctions using that module
        auctionHouse.sunsetModule(toKeycode("MOCK"));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, toKeycode("MOCK"));
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_success() external whenAuctionModuleIsInstalled {
        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (
            Keycode lotAuctionType,
            address lotOwner,
            ERC20 lotBaseToken,
            ERC20 lotQuoteToken,
            IHooks lotHooks,
            IAllowlist lotAllowlist,
            Keycode lotDerivativeType,
            bytes memory lotDerivativeParams,
            bool lotWrapDerivative,
            Keycode lotCondenserType
        ) = auctionHouse.lotRouting(lotId);
        assertEq(fromKeycode(lotAuctionType), fromKeycode(routingParams.auctionType));
        assertEq(lotOwner, address(this));
        assertEq(address(lotBaseToken), address(baseToken));
        assertEq(address(lotQuoteToken), address(quoteToken));
        assertEq(address(lotHooks), address(0));
        assertEq(address(lotAllowlist), address(0));
        assertEq(fromKeycode(lotDerivativeType), "");
        assertEq(lotDerivativeParams, abi.encode(""));
        assertEq(lotWrapDerivative, false);
        assertEq(fromKeycode(lotCondenserType), "");
    }
}
