// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV1} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Veecode, toKeycode} from "src/modules/Modules.sol";

contract RemoveProhibitedModuleFunctionTest is Test {
    WithModules internal withModules;

    function setUp() external {
        withModules = new MockWithModules(address(this));
    }

    modifier whenAModuleFunctionIsProhibited() {
        withModules.addProhibitedModuleFunction(MockModuleV1.prohibited.selector);
        _;
    }

    function testReverts_whenUnauthorized() external whenAModuleFunctionIsProhibited() {
        address alice = address(0x1);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        withModules.removeProhibitedModuleFunction(MockModuleV1.prohibited.selector);
    }

    function testReverts_whenNotProhibited() external {
        bytes memory err = abi.encodeWithSelector(WithModules.ModuleFunctionInvalid.selector, MockModuleV1.mock.selector);
        vm.expectRevert(err);

        withModules.removeProhibitedModuleFunction(MockModuleV1.mock.selector);
    }

    function testReverts_whenZero() external {
        bytes memory err = abi.encodeWithSelector(WithModules.ModuleFunctionInvalid.selector, bytes4(0));
        vm.expectRevert(err);

        // Set as prohibited again
        withModules.removeProhibitedModuleFunction(bytes4(0));
    }

    function test_success() external whenAModuleFunctionIsProhibited() {
        // Remove
        withModules.removeProhibitedModuleFunction(MockModuleV1.prohibited.selector);

        // Check that the selector is removed
        uint256 functionsCount = withModules.prohibitedModuleFunctionsCount();
        assertEq(functionsCount, 0);
    }
}