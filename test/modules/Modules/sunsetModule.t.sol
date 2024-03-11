// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV1} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, toKeycode, fromKeycode} from "src/modules/Modules.sol";

contract SunsetModuleTest is Test {
    WithModules internal _withModules;
    MockModuleV1 internal _mockModule;

    function setUp() external {
        _withModules = new MockWithModules(address(this));
        _mockModule = new MockModuleV1(address(_withModules));
    }

    modifier whenVersion1IsInstalled() {
        _withModules.installModule(_mockModule);
        _;
    }

    function testReverts_whenUnauthorized() external whenVersion1IsInstalled {
        address alice = address(0x1);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        _withModules.sunsetModule(toKeycode("MOCK"));
    }

    function testReverts_whenModuleIsNotInstalled() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 0);
        vm.expectRevert(err);

        _withModules.sunsetModule(toKeycode("MOCK"));
    }

    function testReverts_whenModuleAlreadySunset() external whenVersion1IsInstalled {
        // Sunset the module
        _withModules.sunsetModule(toKeycode("MOCK"));

        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleAlreadySunset.selector, toKeycode("MOCK"));
        vm.expectRevert(err);

        // Sunset the module again
        _withModules.sunsetModule(toKeycode("MOCK"));
    }

    function test_success() external whenVersion1IsInstalled {
        // Sunset the module
        _withModules.sunsetModule(toKeycode("MOCK"));

        // Assert that the status has been changed
        (, bool sunset) = _withModules.getModuleStatus(toKeycode("MOCK"));
        assertEq(sunset, true);

        // Check that the modules array remains the same
        uint256 modulesCount = _withModules.modulesCount();
        assertEq(modulesCount, 1);
        assertEq(fromKeycode(_withModules.modules(0)), "MOCK");
    }
}
