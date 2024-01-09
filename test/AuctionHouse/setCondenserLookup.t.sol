// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAuctionModule} from "test/modules/Auction/MockAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/Derivative/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";

// Auctions
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

// Modules
import {
    Keycode,
    toKeycode,
    fromKeycode,
    Veecode,
    wrapVeecode,
    fromVeecode,
    WithModules,
    Module
} from "src/modules/Modules.sol";

contract SetCondenserLookupTest is Test {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAuctionModule internal mockAuctionModule;
    MockDerivativeModule internal mockDerivativeModule;
    MockCondenserModule internal mockCondenserModule;

    AuctionHouse internal auctionHouse;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse();
        mockAuctionModule = new MockAuctionModule(address(auctionHouse));
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockCondenserModule = new MockCondenserModule(address(auctionHouse));
    }

    modifier whenAuctionModuleIsInstalled() {
        auctionHouse.installModule(mockAuctionModule);
        _;
    }

    modifier whenDerivativeModuleIsInstalled() {
        auctionHouse.installModule(mockDerivativeModule);
        _;
    }

    modifier whenCondenserModuleIsInstalled() {
        auctionHouse.installModule(mockCondenserModule);
        _;
    }

    // addCondenserLookup
    // [X] reverts if not the owner
    // [X] reverts if auction keycode is 0
    // [X] reverts if derivative keycode is 0
    // [X] reverts if auction module is not an auction
    // [X] reverts if derivative module is not a derivative
    // [X] reverts if condenser keycode is not 0 and condenser module is not a condenser
    // [X] unsets if condenser keycode is 0
    // [X] sets the condenser lookup values

    function testReverts_whenUnauthorized() external {
        address alice = address(0x1);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode("DERV"), toKeycode("COND"));
    }

    function testReverts_whenAuctionKeycodeIsEmpty() external {
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidCondenser.selector,
            toKeycode(""),
            toKeycode("DERV"),
            toKeycode("COND")
        );
        vm.expectRevert(err);

        auctionHouse.setCondenserLookup(toKeycode(""), toKeycode("DERV"), toKeycode("COND"));
    }

    function testReverts_whenDerivativeKeycodeIsEmpty() external {
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidCondenser.selector,
            toKeycode("MOCK"),
            toKeycode(""),
            toKeycode("COND")
        );
        vm.expectRevert(err);

        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode(""), toKeycode("COND"));
    }

    function testReverts_whenAuctionModuleNotInstalled() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 0);
        vm.expectRevert(err);

        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode("DERV"), toKeycode("COND"));
    }

    function testReverts_whenAuctionTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidCondenser.selector,
            toKeycode("DERV"),
            toKeycode("DERV"),
            toKeycode("COND")
        );
        vm.expectRevert(err);

        auctionHouse.setCondenserLookup(toKeycode("DERV"), toKeycode("DERV"), toKeycode("COND"));
    }

    function testReverts_whenDerivativeModuleNotInstalled() external whenAuctionModuleIsInstalled {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("DERV"), 0);
        vm.expectRevert(err);

        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode("DERV"), toKeycode("COND"));
    }

    function testReverts_whenDerivativeTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidCondenser.selector,
            toKeycode("MOCK"),
            toKeycode("MOCK"),
            toKeycode("COND")
        );
        vm.expectRevert(err);

        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode("MOCK"), toKeycode("COND"));
    }

    function testReverts_whenCondenserModuleNotInstalled()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("COND"), 0);
        vm.expectRevert(err);

        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode("DERV"), toKeycode("COND"));
    }

    function testReverts_whenCondenserTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidCondenser.selector,
            toKeycode("MOCK"),
            toKeycode("DERV"),
            toKeycode("DERV")
        );
        vm.expectRevert(err);

        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode("DERV"), toKeycode("DERV"));
    }

    function test_success_whenCondenserKeycodeIsEmpty()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode("DERV"), toKeycode(""));

        Keycode condenserKeycode =
            auctionHouse.condenserLookup(toKeycode("MOCK"), toKeycode("DERV"));
        assertEq(fromKeycode(condenserKeycode), "");
    }

    function test_success_whenCondenserKeycodeIsNotEmpty()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        auctionHouse.setCondenserLookup(toKeycode("MOCK"), toKeycode("DERV"), toKeycode("COND"));

        Keycode condenserKeycode =
            auctionHouse.condenserLookup(toKeycode("MOCK"), toKeycode("DERV"));
        assertEq(fromKeycode(condenserKeycode), "COND");
    }
}
