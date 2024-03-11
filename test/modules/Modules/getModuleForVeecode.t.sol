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
        Module module = _withModules.getModuleForVeecode(_mockModule.VEECODE());

        assertEq(address(module), address(0));
    }

    function test_WhenAMatchingModuleIsFound() external whenAModuleIsInstalled {
        Module module = _withModules.getModuleForVeecode(_mockModule.VEECODE());

        assertEq(address(module), address(_mockModule));
    }
}
