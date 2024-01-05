// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV1} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Veecode, toKeycode} from "src/modules/Modules.sol";

contract ExecOnModule is Test {
    WithModules internal withModules;
    MockModuleV1 internal mockModule;

    function setUp() external {
        withModules = new MockWithModules(address(this));
        mockModule = new MockModuleV1(address(withModules));
    }

    modifier whenVersion1IsInstalled() {
        withModules.installModule(mockModule);
        _;
    }

    function testReverts_whenUnauthorized() external whenVersion1IsInstalled {
        address alice = address(0x1);
        Veecode veecode = mockModule.VEECODE();

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        withModules.execOnModule(veecode, abi.encodeWithSelector(MockModuleV1.mock.selector));
    }

    function testReverts_whenModuleNotInstalled() external {
        Veecode veecode = mockModule.VEECODE();

        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 1);
        vm.expectRevert(err);

        withModules.execOnModule(veecode, abi.encodeWithSelector(MockModuleV1.mock.selector));
    }

    function testReverts_whenFunctionIsProhibited() external whenVersion1IsInstalled {
        Veecode veecode = mockModule.VEECODE();

        // Call the function
        withModules.execOnModule(veecode, abi.encodeWithSelector(MockModuleV1.prohibited.selector));

        // Set it as prohibited
        withModules.addProhibitedModuleFunction(MockModuleV1.prohibited.selector);

        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleFunctionProhibited.selector, veecode, MockModuleV1.prohibited.selector
        );
        vm.expectRevert(err);

        withModules.execOnModule(veecode, abi.encodeWithSelector(MockModuleV1.prohibited.selector));
    }

    function test_success() external whenVersion1IsInstalled {
        bytes memory returnData = withModules.execOnModule(
            mockModule.VEECODE(), abi.encodeWithSelector(MockModuleV1.mock.selector)
        );

        // Decode the return data
        (bool returnValue) = abi.decode(returnData, (bool));

        assertEq(returnValue, true);
    }
}
