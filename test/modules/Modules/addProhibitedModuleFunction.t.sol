// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV1} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Veecode, toKeycode} from "src/modules/Modules.sol";

contract AddProhibitedModuleFunctionTest is Test {
    WithModules internal withModules;

    function setUp() external {
        withModules = new MockWithModules(address(this));
    }

    function testReverts_whenUnauthorized() external {
        address alice = address(0x1);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        withModules.addProhibitedModuleFunction(MockModuleV1.mock.selector);
    }

    function testReverts_whenDuplicate() external {
        // Set as prohibited
        withModules.addProhibitedModuleFunction(MockModuleV1.prohibited.selector);

        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleFunctionInvalid.selector, MockModuleV1.prohibited.selector
        );
        vm.expectRevert(err);

        // Set as prohibited again
        withModules.addProhibitedModuleFunction(MockModuleV1.prohibited.selector);
    }

    function testReverts_whenZero() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleFunctionInvalid.selector, bytes4(0));
        vm.expectRevert(err);

        // Set as prohibited again
        withModules.addProhibitedModuleFunction(bytes4(0));
    }

    function test_success() external {
        // Set as prohibited
        withModules.addProhibitedModuleFunction(MockModuleV1.prohibited.selector);

        // Check that the selector is added
        uint256 functionsCount = withModules.prohibitedModuleFunctionsCount();
        assertEq(functionsCount, 1);
        assertEq(withModules.prohibitedModuleFunctions(0), MockModuleV1.prohibited.selector);

        // Add another
        withModules.addProhibitedModuleFunction(MockModuleV1.prohibitedTwo.selector);

        // Check that the selector is added
        functionsCount = withModules.prohibitedModuleFunctionsCount();
        assertEq(functionsCount, 2);
        assertEq(withModules.prohibitedModuleFunctions(0), MockModuleV1.prohibited.selector);
        assertEq(withModules.prohibitedModuleFunctions(1), MockModuleV1.prohibitedTwo.selector);
    }
}
