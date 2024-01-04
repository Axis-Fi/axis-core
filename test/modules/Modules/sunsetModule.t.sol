// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV1} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Module, toKeycode, fromKeycode} from "src/modules/Modules.sol";

contract SunsetModuleTest is Test {
    WithModules internal withModules;
    MockModuleV1 internal mockModule;

    function setUp() external {
        withModules = new MockWithModules(address(this));
        mockModule = new MockModuleV1(address(withModules));
    }

    modifier whenVersion1IsInstalled() {
        withModules.installModule(mockModule);
        _;
    }

    function testReverts_whenUnauthorized() external whenVersion1IsInstalled() {
        address alice = address(0x1);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        withModules.sunsetModule(toKeycode("MOCK"));
    }

    function testReverts_whenModuleIsNotInstalled() external {
        bytes memory err = abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 0);
        vm.expectRevert(err);

        withModules.sunsetModule(toKeycode("MOCK"));
    }

    function testReverts_whenModuleAlreadySunset() external whenVersion1IsInstalled() {
        // Sunset the module
        withModules.sunsetModule(toKeycode("MOCK"));

        bytes memory err = abi.encodeWithSelector(WithModules.ModuleAlreadySunset.selector, toKeycode("MOCK"));
        vm.expectRevert(err);

        // Sunset the module again
        withModules.sunsetModule(toKeycode("MOCK"));
    }

    function test_success() external whenVersion1IsInstalled() {
        // Sunset the module
        withModules.sunsetModule(toKeycode("MOCK"));

        // Assert that the status has been changed
        ( , bool sunset) = withModules.getModuleStatus(toKeycode("MOCK"));
        assertEq(sunset, true);

        // Check that the modules array remains the same
        uint256 modulesCount = withModules.modulesCount();
        assertEq(modulesCount, 1);
        assertEq(fromKeycode(withModules.modules(0)), "MOCK");
    }
}
