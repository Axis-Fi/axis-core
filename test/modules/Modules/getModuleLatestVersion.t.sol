// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModule, MockUpgradedModule} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, toModuleKeycode} from "src/modules/Modules.sol";

contract GetModuleLatestVersionTest is Test {
    WithModules internal withModules;
    MockModule internal mockModule;

    function setUp() external {
        withModules = new MockWithModules(address(this));
        mockModule = new MockModule(address(withModules));
    }

    modifier whenAModuleIsInstalled() {
        // Install the module
        withModules.installModule(mockModule);
        _;
    }

    function test_WhenAMatchingModuleCannotBeFound() external {
        uint8 version = withModules.getModuleLatestVersion(toModuleKeycode("MOCK"));

        assertEq(version, 0);
    }

    function test_WhenAMatchingModuleIsFound() external whenAModuleIsInstalled {
        uint8 version = withModules.getModuleLatestVersion(toModuleKeycode("MOCK"));

        assertEq(version, 1);
    }

    function test_WhenMultipleVersionsAreFound() external whenAModuleIsInstalled {
        // Install an upgraded module
        MockUpgradedModule upgradedMockModule = new MockUpgradedModule(address(withModules));
        // TODO change to upgradeModule
        withModules.installModule(upgradedMockModule);

        uint8 version = withModules.getModuleLatestVersion(toModuleKeycode("MOCK"));

        assertEq(version, 2);
    }
}
