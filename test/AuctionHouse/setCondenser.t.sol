// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAuctionModule} from "test/modules/Auction/MockAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

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

contract SetCondenserTest is Test, Permit2User {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAuctionModule internal mockAuctionModule;
    MockDerivativeModule internal mockDerivativeModule;
    MockCondenserModule internal mockCondenserModule;

    AuctionHouse internal auctionHouse;

    address internal protocol = address(0x2);

    Veecode internal auctionVeecode;
    Veecode internal derivativeVeecode;
    Veecode internal condenserVeecode;
    Veecode internal blankVeecode;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(protocol, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAuctionModule(address(auctionHouse));
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockCondenserModule = new MockCondenserModule(address(auctionHouse));

        auctionVeecode = mockAuctionModule.VEECODE();
        derivativeVeecode = mockDerivativeModule.VEECODE();
        condenserVeecode = mockCondenserModule.VEECODE();
        blankVeecode = toVeecode("");
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

    // setCondenser
    // [X] reverts if not the owner
    // [X] reverts if auction Veecode is 0
    // [X] reverts if derivative Veecode is 0
    // [X] reverts if auction module is not an auction
    // [X] reverts if derivative Veecode is not a derivative
    // [X] reverts if condenser Veecode is not 0 and condenser module is not a condenser
    // [X] unsets if condenser Veecode is 0
    // [X] sets the condenser lookup values

    function testReverts_whenUnauthorized() external {
        address alice = address(0x1);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        auctionHouse.setCondenser(auctionVeecode, derivativeVeecode, condenserVeecode);
    }

    function testReverts_whenAuctionVeecodeIsEmpty() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.setCondenser(blankVeecode, derivativeVeecode, condenserVeecode);
    }

    function testReverts_whenDerivativeVeecodeIsEmpty() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.setCondenser(auctionVeecode, blankVeecode, condenserVeecode);
    }

    function testReverts_whenAuctionModuleNotInstalled() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 1);
        vm.expectRevert(err);

        auctionHouse.setCondenser(auctionVeecode, derivativeVeecode, condenserVeecode);
    }

    function testReverts_whenAuctionTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err =
            abi.encodeWithSelector(Auctioneer.InvalidModuleType.selector, derivativeVeecode);
        vm.expectRevert(err);

        auctionHouse.setCondenser(derivativeVeecode, derivativeVeecode, condenserVeecode);
    }

    function testReverts_whenDerivativeModuleNotInstalled() external whenAuctionModuleIsInstalled {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("DERV"), 1);
        vm.expectRevert(err);

        auctionHouse.setCondenser(auctionVeecode, derivativeVeecode, condenserVeecode);
    }

    function testReverts_whenDerivativeTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err =
            abi.encodeWithSelector(Auctioneer.InvalidModuleType.selector, auctionVeecode);
        vm.expectRevert(err);

        auctionHouse.setCondenser(auctionVeecode, auctionVeecode, condenserVeecode);
    }

    function testReverts_whenCondenserModuleNotInstalled()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("COND"), 1);
        vm.expectRevert(err);

        auctionHouse.setCondenser(auctionVeecode, derivativeVeecode, condenserVeecode);
    }

    function testReverts_whenCondenserTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err =
            abi.encodeWithSelector(Auctioneer.InvalidModuleType.selector, derivativeVeecode);
        vm.expectRevert(err);

        auctionHouse.setCondenser(auctionVeecode, derivativeVeecode, derivativeVeecode);
    }

    function test_success_whenCondenserVeecodeIsEmpty()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        auctionHouse.setCondenser(auctionVeecode, derivativeVeecode, blankVeecode);

        Veecode veecode_ = auctionHouse.condensers(auctionVeecode, derivativeVeecode);
        assertEq(fromVeecode(veecode_), "");
    }

    function test_success_whenCondenserVeecodeIsNotEmpty()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        auctionHouse.setCondenser(auctionVeecode, derivativeVeecode, condenserVeecode);

        Veecode veecode_ = auctionHouse.condensers(auctionVeecode, derivativeVeecode);
        assertEq(fromVeecode(veecode_), fromVeecode(condenserVeecode));
    }
}
