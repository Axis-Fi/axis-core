// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV1, MockModuleV2} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, toKeycode} from "src/modules/Modules.sol";

contract GetModuleStatusTest is Test {
    WithModules internal withModules;
    MockModuleV1 internal mockModule;

    function setUp() external {
        withModules = new MockWithModules(address(this));
        mockModule = new MockModuleV1(address(withModules));
    }

    modifier whenAModuleIsInstalled() {
        // Install the module
        withModules.installModule(mockModule);
        _;
    }

    function test_WhenAMatchingModuleCannotBeFound() external {
        (uint8 moduleLatestVersion, bool moduleIsSunset) = withModules.getModuleStatus(toKeycode("MOCK"));

        assertEq(moduleLatestVersion, 0);
        assertFalse(moduleIsSunset);
    }

    function test_WhenAMatchingModuleIsFound() external whenAModuleIsInstalled {
        (uint8 moduleLatestVersion, bool moduleIsSunset) = withModules.getModuleStatus(toKeycode("MOCK"));

        assertEq(moduleLatestVersion, 1);
        assertFalse(moduleIsSunset);
    }

    function test_WhenMultipleVersionsAreFound() external whenAModuleIsInstalled {
        // Install an upgraded module
        MockModuleV2 upgradedMockModule = new MockModuleV2(address(withModules));
        withModules.installModule(upgradedMockModule);

        (uint8 moduleLatestVersion, bool moduleIsSunset) = withModules.getModuleStatus(toKeycode("MOCK"));

        assertEq(moduleLatestVersion, 2);
        assertFalse(moduleIsSunset);
    }

    function test_WhenAModuleIsSunset() external whenAModuleIsInstalled {
        // Sunset the module
        withModules.sunsetModule(toKeycode("MOCK"));

        (uint8 moduleLatestVersion, bool moduleIsSunset) = withModules.getModuleStatus(toKeycode("MOCK"));

        assertEq(moduleLatestVersion, 1);
        assertTrue(moduleIsSunset);
    }
}
