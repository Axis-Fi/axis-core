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
    toVeecode,
    fromVeecode,
    WithModules,
    Module
} from "src/modules/Modules.sol";

contract SetCondenserTest is Test {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAuctionModule internal mockAuctionModule;
    MockDerivativeModule internal mockDerivativeModule;
    MockCondenserModule internal mockCondenserModule;

    AuctionHouse internal auctionHouse;

    address internal protocol = address(0x2);

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(protocol);
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
        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockCondenserModule.VEECODE()
        );
    }

    function testReverts_whenAuctionKeycodeIsEmpty() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.setCondenser(
            toVeecode(""), mockDerivativeModule.VEECODE(), mockCondenserModule.VEECODE()
        );
    }

    function testReverts_whenDerivativeKeycodeIsEmpty() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(), toVeecode(""), mockCondenserModule.VEECODE()
        );
    }

    function testReverts_whenAuctionModuleNotInstalled() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 0);
        vm.expectRevert(err);

        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockCondenserModule.VEECODE()
        );
    }

    function testReverts_whenAuctionTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.InvalidModuleType.selector, mockDerivativeModule.VEECODE()
        );
        vm.expectRevert(err);

        auctionHouse.setCondenser(
            mockDerivativeModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockCondenserModule.VEECODE()
        );
    }

    function testReverts_whenDerivativeModuleNotInstalled() external whenAuctionModuleIsInstalled {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("DERV"), 0);
        vm.expectRevert(err);

        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockCondenserModule.VEECODE()
        );
    }

    function testReverts_whenDerivativeTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.InvalidModuleType.selector, mockAuctionModule.VEECODE()
        );
        vm.expectRevert(err);

        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(), mockAuctionModule.VEECODE(), mockCondenserModule.VEECODE()
        );
    }

    function testReverts_whenCondenserModuleNotInstalled()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("COND"), 0);
        vm.expectRevert(err);

        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockCondenserModule.VEECODE()
        );
    }

    function testReverts_whenCondenserTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.InvalidModuleType.selector, mockDerivativeModule.VEECODE()
        );
        vm.expectRevert(err);

        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockDerivativeModule.VEECODE()
        );
    }

    function test_success_whenCondenserKeycodeIsEmpty()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(), mockDerivativeModule.VEECODE(), toVeecode("")
        );

        Veecode condenserVeecode =
            auctionHouse.condensers(mockAuctionModule.VEECODE(), mockDerivativeModule.VEECODE());
        assertEq(fromVeecode(condenserVeecode), "");
    }

    function test_success_whenCondenserKeycodeIsNotEmpty()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockCondenserModule.VEECODE()
        );

        Veecode condenserVeecode =
            auctionHouse.condensers(mockAuctionModule.VEECODE(), mockDerivativeModule.VEECODE());
        assertEq(fromVeecode(condenserVeecode), fromVeecode(mockCondenserModule.VEECODE()));
    }
}
