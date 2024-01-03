// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModule, MockUpgradedModule, MockInvalidModule} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Module, moduleFromKeycode, InvalidKeycode} from "src/modules/Modules.sol";

contract InstallModuleTest is Test {
    WithModules internal withModules;
    MockModule internal mockModule;

    function setUp() external {
        withModules = new MockWithModules(address(this));
        mockModule = new MockModule(address(withModules));
    }

    function testReverts_whenPreviousVersionIsInstalled() external {
        // Install version 1
        withModules.installModule(mockModule);

        Module upgradedModule = new MockUpgradedModule(address(withModules));

        bytes memory err = abi.encodeWithSelector(WithModules.ModuleAlreadyInstalled.selector, moduleFromKeycode(mockModule.KEYCODE()), 1);
        vm.expectRevert(err);

        // Install version 2
        withModules.installModule(upgradedModule);
    }

    function testReverts_whenSameVersionIsInstalled() external {
        // Install version 1
        withModules.installModule(mockModule);

        bytes memory err = abi.encodeWithSelector(WithModules.ModuleAlreadyInstalled.selector, moduleFromKeycode(mockModule.KEYCODE()), 1);
        vm.expectRevert(err);

        // Install version 1 again
        withModules.installModule(mockModule);
    }

    function testReverts_whenNewerVersionIsInstalled() external {
        // Install version 2
        Module upgradedModule = new MockUpgradedModule(address(withModules));
        withModules.installModule(upgradedModule);

        bytes memory err = abi.encodeWithSelector(WithModules.ModuleAlreadyInstalled.selector, moduleFromKeycode(upgradedModule.KEYCODE()), 2);
        vm.expectRevert(err);

        // Install version 1
        withModules.installModule(mockModule);
    }

    function testReverts_invalidKeycode() external {
        Module invalidModule = new MockInvalidModule(address(withModules));

        bytes memory err = abi.encodeWithSelector(InvalidKeycode.selector, invalidModule.KEYCODE());
        vm.expectRevert(err);

        withModules.installModule(invalidModule);
    }

    function test_success_whenNoPreviousVersionIsInstalled() external {
        // Install the module
        withModules.installModule(mockModule);

        // Check that the module is installed
        Module module = withModules.getModuleForKeycode(mockModule.KEYCODE());
        assertEq(address(module), address(mockModule));

        // Check that the latest version is recorded
        uint8 version = withModules.getModuleLatestVersion(moduleFromKeycode(mockModule.KEYCODE()));
        assertEq(version, 1);
    }
}
