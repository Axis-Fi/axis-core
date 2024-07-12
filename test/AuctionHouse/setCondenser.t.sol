// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "@forge-std-1.9.1/Test.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAuctionHouse} from "test/AuctionHouse/MockAuctionHouse.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {InvalidVeecode, keycodeFromVeecode} from "src/modules/Modules.sol";

// Modules
import {toKeycode, Veecode, toVeecode, fromVeecode, WithModules} from "src/modules/Modules.sol";

contract SetCondenserTest is Test, Permit2User {
    MockERC20 internal _baseToken;
    MockERC20 internal _quoteToken;
    MockAtomicAuctionModule internal _mockAuctionModule;
    MockDerivativeModule internal _mockDerivativeModule;
    MockCondenserModule internal _mockCondenserModule;

    MockAuctionHouse internal _auctionHouse;

    address internal constant _PROTOCOL = address(0x2);
    address internal constant _OWNER = address(0x3);

    Veecode internal _auctionVeecode;
    Veecode internal _derivativeVeecode;
    Veecode internal _condenserVeecode;
    Veecode internal _blankVeecode;

    function setUp() external {
        _baseToken = new MockERC20("Base Token", "BASE", 18);
        _quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        _auctionHouse = new MockAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _mockAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));
        _mockDerivativeModule = new MockDerivativeModule(address(_auctionHouse));
        _mockCondenserModule = new MockCondenserModule(address(_auctionHouse));

        _auctionVeecode = _mockAuctionModule.VEECODE();
        _derivativeVeecode = _mockDerivativeModule.VEECODE();
        _condenserVeecode = _mockCondenserModule.VEECODE();
        _blankVeecode = toVeecode("");
    }

    modifier whenAuctionModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_mockAuctionModule);
        _;
    }

    modifier whenDerivativeModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_mockDerivativeModule);
        _;
    }

    modifier whenCondenserModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_mockCondenserModule);
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
        _auctionHouse.setCondenser(_auctionVeecode, _derivativeVeecode, _condenserVeecode);
    }

    function testReverts_whenAuctionVeecodeIsEmpty() external {
        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, _blankVeecode);
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_blankVeecode, _derivativeVeecode, _condenserVeecode);
    }

    function testReverts_whenDerivativeVeecodeIsEmpty() external whenAuctionModuleIsInstalled {
        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, _blankVeecode);
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_auctionVeecode, _blankVeecode, _condenserVeecode);
    }

    function testReverts_whenAuctionModuleNotInstalled() external {
        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleNotInstalled.selector, keycodeFromVeecode(_auctionVeecode), 1
        );
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_auctionVeecode, _derivativeVeecode, _condenserVeecode);
    }

    function testReverts_whenAuctionTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_derivativeVeecode, _derivativeVeecode, _condenserVeecode);
    }

    function testReverts_whenDerivativeModuleNotInstalled() external whenAuctionModuleIsInstalled {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("DERV"), 1);
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_auctionVeecode, _derivativeVeecode, _condenserVeecode);
    }

    function testReverts_whenDerivativeTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_auctionVeecode, _auctionVeecode, _condenserVeecode);
    }

    function testReverts_whenCondenserModuleNotInstalled()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("COND"), 1);
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_auctionVeecode, _derivativeVeecode, _condenserVeecode);
    }

    function testReverts_whenCondenserTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_auctionVeecode, _derivativeVeecode, _derivativeVeecode);
    }

    function test_success_whenCondenserVeecodeIsEmpty()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_auctionVeecode, _derivativeVeecode, _blankVeecode);

        Veecode veecode_ = _auctionHouse.condensers(_auctionVeecode, _derivativeVeecode);
        assertEq(fromVeecode(veecode_), "");
    }

    function test_success_whenCondenserVeecodeIsNotEmpty()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        vm.prank(_OWNER);
        _auctionHouse.setCondenser(_auctionVeecode, _derivativeVeecode, _condenserVeecode);

        Veecode veecode_ = _auctionHouse.condensers(_auctionVeecode, _derivativeVeecode);
        assertEq(fromVeecode(veecode_), fromVeecode(_condenserVeecode));
    }
}
