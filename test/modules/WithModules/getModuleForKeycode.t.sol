// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/WithModules/MockWithModules.sol";
import {MockModule} from "test/modules/WithModules/MockModule.sol";

// Contracts
import {WithModules, Module} from "src/modules/Modules.sol";

contract GetModuleForKeycodeTest is Test {
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
        Module module = withModules.getModuleForKeycode(mockModule.KEYCODE());

        assertEq(address(module), address(0));
    }

    function test_WhenAMatchingModuleIsFound() external whenAModuleIsInstalled {
        Module module = withModules.getModuleForKeycode(mockModule.KEYCODE());

        assertEq(address(module), address(mockModule));
    }
}
