// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockWithModules} from "test/modules/Modules/MockWithModules.sol";
import {
    MockModuleV0,
    MockModuleV1,
    MockModuleV2,
    MockModuleV3,
    MockInvalidModule
} from "test/modules/Modules/MockModule.sol";

// Contracts
import {
    WithModules, Module, fromKeycode, toKeycode, InvalidVeecode
} from "src/modules/Modules.sol";

contract InstallModuleTest is Test {
    WithModules internal _withModules;
    MockModuleV1 internal _mockModule;

    function setUp() external {
        _withModules = new MockWithModules(address(this));
        _mockModule = new MockModuleV1(address(_withModules));
    }

    modifier whenVersion1IsInstalled() {
        _withModules.installModule(_mockModule);
        _;
    }

    function testReverts_whenUnauthorized() external {
        address alice = address(0x1);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(alice);
        _withModules.installModule(_mockModule);
    }

    function testReverts_whenSameVersionIsInstalled() external whenVersion1IsInstalled {
        bytes memory err =
            abi.encodeWithSelector(WithModules.InvalidModuleInstall.selector, toKeycode("MOCK"), 1);
        vm.expectRevert(err);

        // Install version 1 again
        _withModules.installModule(_mockModule);
    }

    function testReverts_whenNewerVersionIsInstalled() external whenVersion1IsInstalled {
        // Install version 2
        Module upgradedModule = new MockModuleV2(address(_withModules));
        _withModules.installModule(upgradedModule);

        bytes memory err =
            abi.encodeWithSelector(WithModules.InvalidModuleInstall.selector, toKeycode("MOCK"), 1);
        vm.expectRevert(err);

        // Install version 1
        _withModules.installModule(_mockModule);
    }

    function testReverts_whenInitialVersionZero() external {
        Module moduleZero = new MockModuleV0(address(_withModules));

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, moduleZero.VEECODE());
        vm.expectRevert(err);

        // Install version 0
        _withModules.installModule(moduleZero);
    }

    function testReverts_whenInitialVersionIncorrect() external {
        Module upgradedModule = new MockModuleV2(address(_withModules));

        bytes memory err =
            abi.encodeWithSelector(WithModules.InvalidModuleInstall.selector, toKeycode("MOCK"), 2);
        vm.expectRevert(err);

        // Install version 2 (skips version 1)
        _withModules.installModule(upgradedModule);
    }

    function testReverts_whenNewerVersionSkips() external whenVersion1IsInstalled {
        Module upgradedModule = new MockModuleV3(address(_withModules));

        bytes memory err =
            abi.encodeWithSelector(WithModules.InvalidModuleInstall.selector, toKeycode("MOCK"), 3);
        vm.expectRevert(err);

        // Install version 3
        _withModules.installModule(upgradedModule);
    }

    function testReverts_invalidVeecode() external {
        Module invalidModule = new MockInvalidModule(address(_withModules));

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, invalidModule.VEECODE());
        vm.expectRevert(err);

        _withModules.installModule(invalidModule);
    }

    function test_whenNoPreviousVersionIsInstalled() external {
        // Install the module
        _withModules.installModule(_mockModule);

        // Check that the module is installed
        Module module = _withModules.getModuleForVeecode(_mockModule.VEECODE());
        assertEq(address(module), address(_mockModule));

        // Check that the latest version is recorded
        (uint8 moduleLatestVersion,) = _withModules.getModuleStatus(toKeycode("MOCK"));
        assertEq(moduleLatestVersion, 1);

        // Check that the modules array is updated
        uint256 modulesCount = _withModules.modulesCount();
        assertEq(modulesCount, 1);
        assertEq(fromKeycode(_withModules.modules(0)), "MOCK");
    }

    function test_whenPreviousVersionIsInstalled() external whenVersion1IsInstalled {
        Module upgradedModule = new MockModuleV2(address(_withModules));

        // Upgrade to version 2
        _withModules.installModule(upgradedModule);

        // Check that the module is installed
        Module upgradedModule_ = _withModules.getModuleForVeecode(upgradedModule.VEECODE());
        assertEq(address(upgradedModule_), address(upgradedModule));

        // Check that the version is correct
        (uint8 moduleLatestVersion, bool moduleIsSunset) =
            _withModules.getModuleStatus(toKeycode("MOCK"));
        assertEq(moduleLatestVersion, 2);
        assertEq(moduleIsSunset, false);

        // Check that the previous version is still installed
        Module previousModule_ = _withModules.getModuleForVeecode(_mockModule.VEECODE());
        assertEq(address(previousModule_), address(_mockModule));

        // Check that the modules array remains the same
        uint256 modulesCount = _withModules.modulesCount();
        assertEq(modulesCount, 1);
        assertEq(fromKeycode(_withModules.modules(0)), "MOCK");
    }

    function test_whenModuleIsSunset() external whenVersion1IsInstalled {
        // Sunset version 1
        _withModules.sunsetModule(toKeycode("MOCK"));

        // Install version 2
        Module upgradedModule = new MockModuleV2(address(_withModules));
        _withModules.installModule(upgradedModule);

        // Check that the module is installed
        Module upgradedModule_ = _withModules.getModuleForVeecode(upgradedModule.VEECODE());
        assertEq(address(upgradedModule_), address(upgradedModule));

        // Check that the module is re-enabled
        (uint8 moduleLatestVersion, bool moduleIsSunset) =
            _withModules.getModuleStatus(toKeycode("MOCK"));
        assertEq(moduleLatestVersion, 2);
        assertEq(moduleIsSunset, false);

        // Check that the modules array remains the same
        uint256 modulesCount = _withModules.modulesCount();
        assertEq(modulesCount, 1);
        assertEq(fromKeycode(_withModules.modules(0)), "MOCK");
    }
}
