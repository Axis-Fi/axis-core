// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {MockModuleV0, MockModuleV1, MockModuleV2, MockModuleV3, MockInvalidModule} from "test/modules/Modules/MockModule.sol";

// Contracts
import {WithModules, Module, Keycode, fromKeycode, toKeycode, wrapVeecode, InvalidVeecode} from "src/modules/Modules.sol";

contract InstallModuleTest is Test {
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

    function testReverts_whenUnauthorized() external {
        address alice = address(0x1);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        withModules.installModule(mockModule);
    }

    function testReverts_whenSameVersionIsInstalled() external whenVersion1IsInstalled() {
        bytes memory err = abi.encodeWithSelector(WithModules.InvalidModuleInstall.selector, toKeycode("MOCK"), 1);
        vm.expectRevert(err);

        // Install version 1 again
        withModules.installModule(mockModule);
    }

    function testReverts_whenNewerVersionIsInstalled() external whenVersion1IsInstalled() {
        // Install version 2
        Module upgradedModule = new MockModuleV2(address(withModules));
        withModules.installModule(upgradedModule);

        bytes memory err = abi.encodeWithSelector(WithModules.InvalidModuleInstall.selector, toKeycode("MOCK"), 1);
        vm.expectRevert(err);

        // Install version 1
        withModules.installModule(mockModule);
    }

    function testReverts_whenInitialVersionZero() external {
        Module moduleZero = new MockModuleV0(address(withModules));

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, moduleZero.VEECODE());
        vm.expectRevert(err);

        // Install version 0
        withModules.installModule(moduleZero);
    }

    function testReverts_whenInitialVersionIncorrect() external {
        Module upgradedModule = new MockModuleV2(address(withModules));

        bytes memory err = abi.encodeWithSelector(WithModules.InvalidModuleInstall.selector, toKeycode("MOCK"), 2);
        vm.expectRevert(err);

        // Install version 2 (skips version 1)
        withModules.installModule(upgradedModule);
    }

    function testReverts_whenNewerVersionSkips() external whenVersion1IsInstalled() {
        Module upgradedModule = new MockModuleV3(address(withModules));

        bytes memory err = abi.encodeWithSelector(WithModules.InvalidModuleInstall.selector, toKeycode("MOCK"), 3);
        vm.expectRevert(err);

        // Install version 3
        withModules.installModule(upgradedModule);
    }

    function testReverts_invalidVeecode() external {
        Module invalidModule = new MockInvalidModule(address(withModules));

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, invalidModule.VEECODE());
        vm.expectRevert(err);

        withModules.installModule(invalidModule);
    }

    function test_whenNoPreviousVersionIsInstalled() external {
        // Install the module
        withModules.installModule(mockModule);

        // Check that the module is installed
        Module module = withModules.getModuleForVeecode(mockModule.VEECODE());
        assertEq(address(module), address(mockModule));

        // Check that the latest version is recorded
        (uint8 moduleLatestVersion, ) = withModules.getModuleStatus(toKeycode("MOCK"));
        assertEq(moduleLatestVersion, 1);

        // Check that the modules array is updated
        Keycode[] memory modules = withModules.getModules();
        assertEq(modules.length, 1);
        assertEq(fromKeycode(modules[0]), "MOCK");
    }

    function test_whenPreviousVersionIsInstalled() external whenVersion1IsInstalled() {
        Module upgradedModule = new MockModuleV2(address(withModules));

        // Upgrade to version 2
        withModules.installModule(upgradedModule);

        // Check that the module is installed
        Module upgradedModule_ = withModules.getModuleForVeecode(upgradedModule.VEECODE());
        assertEq(address(upgradedModule_), address(upgradedModule));

        // Check that the version is correct
        (uint8 moduleLatestVersion, bool moduleIsSunset) = withModules.getModuleStatus(toKeycode("MOCK"));
        assertEq(moduleLatestVersion, 2);
        assertEq(moduleIsSunset, false);

        // Check that the previous version is still installed
        Module previousModule_ = withModules.getModuleForVeecode(mockModule.VEECODE());
        assertEq(address(previousModule_), address(mockModule));

        // Check that the modules array remains the same
        Keycode[] memory modules = withModules.getModules();
        assertEq(modules.length, 1);
        assertEq(fromKeycode(modules[0]), "MOCK");
    }

    function test_whenModuleIsSunset() external whenVersion1IsInstalled() {
        // Sunset version 1
        withModules.sunsetModule(toKeycode("MOCK"));

        // Install version 2
        Module upgradedModule = new MockModuleV2(address(withModules));
        withModules.installModule(upgradedModule);

        // Check that the module is installed
        Module upgradedModule_ = withModules.getModuleForVeecode(upgradedModule.VEECODE());
        assertEq(address(upgradedModule_), address(upgradedModule));

        // Check that the module is re-enabled
        (uint8 moduleLatestVersion, bool moduleIsSunset) = withModules.getModuleStatus(toKeycode("MOCK"));
        assertEq(moduleLatestVersion, 2);
        assertEq(moduleIsSunset, false);
    }
}
