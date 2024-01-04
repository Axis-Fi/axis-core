// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV1} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Module} from "src/modules/Modules.sol";

contract GetModuleForVeecodeTest is Test {
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
        Module module = withModules.getModuleForVeecode(mockModule.VEECODE());

        assertEq(address(module), address(0));
    }

    function test_WhenAMatchingModuleIsFound() external whenAModuleIsInstalled {
        Module module = withModules.getModuleForVeecode(mockModule.VEECODE());

        assertEq(address(module), address(mockModule));
    }
}
