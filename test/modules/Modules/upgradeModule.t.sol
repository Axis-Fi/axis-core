// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModule, MockUpgradedModule, MockInvalidModule} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Module, Keycode, fromKeycode, toKeycode, toModuleKeycode, moduleFromKeycode, InvalidKeycode, moduleFromKeycode} from "src/modules/Modules.sol";

contract UpgradeModuleTest is Test {
    WithModules internal withModules;
    MockModule internal mockModule;

    function setUp() external {
        withModules = new MockWithModules(address(this));
        mockModule = new MockModule(address(withModules));
    }

    function test_whenPreviousVersionIsInstalled() external {
        // Install version 1
        withModules.installModule(mockModule);

        Module upgradedModule = new MockUpgradedModule(address(withModules));

        // Upgrade to version 2
        withModules.upgradeModule(upgradedModule);

        // Check that the module is installed
        Module upgradedModule_ = withModules.getModuleForKeycode(upgradedModule.KEYCODE());
        assertEq(address(upgradedModule_), address(upgradedModule));

        // Check that the version is correct
        uint8 upgradedModuleVersion_ = withModules.getModuleLatestVersion(moduleFromKeycode(upgradedModule.KEYCODE()));
        assertEq(upgradedModuleVersion_, 2);

        // Check that the new version is NOT sunset
        bool upgradedModuleIsSunset_ = withModules.moduleSunset(upgradedModule.KEYCODE());
        assertFalse(upgradedModuleIsSunset_);

        // Check that the previous version is still installed
        Module previousModule_ = withModules.getModuleForKeycode(mockModule.KEYCODE());
        assertEq(address(previousModule_), address(mockModule));

        // Check that the previous version is sunset
        bool previousModuleIsSunset_ = withModules.moduleSunset(mockModule.KEYCODE());
        assertTrue(previousModuleIsSunset_);

        // Check that the modules array is updated
        Keycode[] memory modules = withModules.getModules();
        assertEq(modules.length, 2);
        assertEq(fromKeycode(modules[0]), fromKeycode(toKeycode(toModuleKeycode("MOCK"), 1)));
        assertEq(fromKeycode(modules[1]), fromKeycode(toKeycode(toModuleKeycode("MOCK"), 2)));
    }

    function testReverts_whenSameVersionIsInstalled() external {
        // Install version 1
        withModules.installModule(mockModule);

        bytes memory err = abi.encodeWithSelector(WithModules.ModuleAlreadyInstalled.selector, moduleFromKeycode(mockModule.KEYCODE()), 1);
        vm.expectRevert(err);

        // Upgrade to version 1
        withModules.upgradeModule(mockModule);
    }

    function testReverts_whenNewerVersionIsInstalled() external {
        // Install version 2
        Module upgradedModule = new MockUpgradedModule(address(withModules));
        withModules.installModule(upgradedModule);

        bytes memory err = abi.encodeWithSelector(WithModules.ModuleAlreadyInstalled.selector, moduleFromKeycode(upgradedModule.KEYCODE()), 2);
        vm.expectRevert(err);

        // Upgrade to version 1
        withModules.upgradeModule(mockModule);
    }

    function testReverts_invalidKeycode() external {
        Module invalidModule = new MockInvalidModule(address(withModules));

        bytes memory err = abi.encodeWithSelector(InvalidKeycode.selector, invalidModule.KEYCODE());
        vm.expectRevert(err);

        withModules.upgradeModule(invalidModule);
    }

    function testReverts_whenNoVersionIsInstalled() external {
        bytes memory err = abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, moduleFromKeycode(mockModule.KEYCODE()), 0);
        vm.expectRevert(err);

        withModules.upgradeModule(mockModule);
    }
}