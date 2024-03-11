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
    WithModules internal _withModules;
    MockModuleV1 internal _mockModule;

    function setUp() external {
        _withModules = new MockWithModules(address(this));
        _mockModule = new MockModuleV1(address(_withModules));
    }

    modifier whenAModuleIsInstalled() {
        // Install the module
        _withModules.installModule(_mockModule);
        _;
    }

    function test_WhenAMatchingModuleCannotBeFound() external {
        (uint8 moduleLatestVersion, bool moduleIsSunset) =
            _withModules.getModuleStatus(toKeycode("MOCK"));

        assertEq(moduleLatestVersion, 0);
        assertFalse(moduleIsSunset);
    }

    function test_WhenAMatchingModuleIsFound() external whenAModuleIsInstalled {
        (uint8 moduleLatestVersion, bool moduleIsSunset) =
            _withModules.getModuleStatus(toKeycode("MOCK"));

        assertEq(moduleLatestVersion, 1);
        assertFalse(moduleIsSunset);
    }

    function test_WhenMultipleVersionsAreFound() external whenAModuleIsInstalled {
        // Install an upgraded module
        MockModuleV2 upgradedMockModule = new MockModuleV2(address(_withModules));
        _withModules.installModule(upgradedMockModule);

        (uint8 moduleLatestVersion, bool moduleIsSunset) =
            _withModules.getModuleStatus(toKeycode("MOCK"));

        assertEq(moduleLatestVersion, 2);
        assertFalse(moduleIsSunset);
    }

    function test_WhenAModuleIsSunset() external whenAModuleIsInstalled {
        // Sunset the module
        _withModules.sunsetModule(toKeycode("MOCK"));

        (uint8 moduleLatestVersion, bool moduleIsSunset) =
            _withModules.getModuleStatus(toKeycode("MOCK"));

        assertEq(moduleLatestVersion, 1);
        assertTrue(moduleIsSunset);
    }
}
