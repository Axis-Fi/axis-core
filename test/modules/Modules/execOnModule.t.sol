// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV1} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Module, Veecode, toKeycode} from "src/modules/Modules.sol";

contract ExecOnModule is Test {
    MockWithModules internal withModules;
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

    function testReverts_whenFunctionIsOnlyInternal() external whenVersion1IsInstalled {
        Veecode veecode = mockModule.VEECODE();

        // This mimics that the function was called from the outside (e.g. governance) via execOnModule
        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleExecutionReverted.selector,
            abi.encodeWithSelector(Module.Module_OnlyInternal.selector)
        );
        vm.expectRevert(err);

        withModules.execOnModule(veecode, abi.encodeWithSelector(MockModuleV1.prohibited.selector));
    }

    function test_whenFunctionIsOnlyInternal_whenParentIsCalling()
        external
        whenVersion1IsInstalled
    {
        Veecode veecode = mockModule.VEECODE();

        // Mimic the parent contract calling a protected function directly
        bool returnValue = withModules.callProhibited(veecode);
        assertEq(returnValue, true);
    }

    function testReverts_whenFunctionIsOnlyInternal_whenExternalIsCalling()
        external
        whenVersion1IsInstalled
    {
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Mimic the parent contract calling a protected function directly
        mockModule.prohibited();
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
