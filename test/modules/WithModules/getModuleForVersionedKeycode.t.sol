// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/WithModules/MockWithModules.sol";
import {MockModule} from "test/modules/WithModules/MockModule.sol";

// Contracts
import {WithModules} from "src/modules/Modules.sol";

contract GetModuleForVersionedKeycodeTest is Test {
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

    function test_WhenAMatchingModuleAndVersionCannotBeFound() external whenAModuleIsInstalled {
        // It should revert.
        assertTrue(false);
    }

    function test_WhenAMatchingModuleIsFoundButNoVersion() external whenAModuleIsInstalled {
        // It should revert.
        assertTrue(false);
    }

    function test_WhenAMatchingModuleAndVersionIsFound() external whenAModuleIsInstalled {
        // It should return the module.
        assertTrue(false);
    }
}
