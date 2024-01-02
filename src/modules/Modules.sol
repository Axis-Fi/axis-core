/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Owned} from "lib/solmate/src/auth/Owned.sol";

// Inspired by Default framework keycode management of dependencies and based on the Modules pattern

// Keycode functions

type Keycode is bytes5; // 3-5 characters, A-Z only first 3, blank or A-Z for the rest

error TargetNotAContract(address target_);
error InvalidKeycode(Keycode keycode_);

// solhint-disable-next-line func-visibility
function toKeycode(bytes5 keycode_) pure returns (Keycode) {
    return Keycode.wrap(keycode_);
}

// solhint-disable-next-line func-visibility
function fromKeycode(Keycode keycode_) pure returns (bytes10) {
    return Keycode.unwrap(keycode_);
}

// solhint-disable-next-line func-visibility
function ensureContract(address target_) view {
    if (target_.code.length == 0) revert TargetNotAContract(target_);
}

// solhint-disable-next-line func-visibility
function ensureValidKeycode(Keycode keycode_) pure {
    bytes10 unwrapped = Keycode.unwrap(keycode_);
    for (uint256 i; i < 5; ) {
        bytes1 char = unwrapped[i];
        if (i < 3) {
            // First 3 characters must be A-Z
            if (char < 0x41 || char > 0x5A) revert InvalidKeycode(keycode_);
        } else {
            // Characters after the first 3 can be blank or A-Z
            if (char != 0x00 && (char < 0x41 || char > 0x5A)) revert InvalidKeycode(keycode_);
        }
        unchecked {
            i++;
        }
    }
}


abstract contract WithModules is Owned {
    // ========= ERRORS ========= //
    error InvalidModule();
    error InvalidModuleUpgrade(Keycode keycode_, uint8 version_);
    error ModuleAlreadyInstalled(Keycode keycode_);
    error ModuleNotInstalled(Keycode keycode_);
    error ModuleExecutionReverted(bytes error_);
    error ModuleAlreadySunset(Keycode keycode_, uint8 version_);
    error ModuleSunset(Keycode keycode_, uint8 version_);

    // ========= MODULE MANAGEMENT ========= //

    struct Version {
        Module module;
        bool sunset;
    }

    struct Mod {
        uint8 latestVersion;
        mapping(uint8 => Version) versions;
    }

    /// @notice Array of all modules currently installed.
    Keycode[] public modules;

    /// @notice Mapping of Keycode to Module data.
    mapping(Keycode => Mod) public moduleData;

    function installModule(Module newModule_) external onlyOwner {
        // Validate new module and get its keycode and version
        // This function checks that the version is one greater than the latest version, which in this case should be 1
        // The module is installed check below validates that the latest version is zero
        (Keycode keycode, uint8 version) = _validateModule(newModule_);

        // Check that a module with this keycode is not already installed
        // If this reverts, then the new module should be installed via upgradeModule
        if (_moduleIsInstalled(keycode))
            revert ModuleAlreadyInstalled(keycode);

        // Store module data
        Mod storage mod = moduleData[keycode];
        mod.latestVersion = version;
        mod.versions[version] = Version(newModule_, false);
        modules.push(keycode);

        // Initialize the module
        newModule_.INIT();
    }

    /// @notice Prevents future use of module, but functionality remains for existing users. Modules should implement functionality such that creation functions are disabled if sunset.
    /// @dev    Sunsets the latest version the module and doesn't allow further use for creation. If you want to replace the module, use upgradeModule.
    function sunsetModule(Keycode keycode_) external onlyOwner {
        // Check that the module is installed
        if (!_moduleIsInstalled(keycode_)) revert ModuleNotInstalled(keycode_);

        // Check that the module is not already sunset
        Mod storage mod = moduleData[keycode_];
        uint8 latest = mod.latestVersion;
        if (mod.versions[latest].sunset) revert ModuleAlreadySunset(keycode_, latest);

        // Set the module to sunset
        mod.versions[latest].sunset = true;
    }

    /// @notice Upgrades a module to a new version. The current version will be sunset.
    /// @dev Only one version of a module can be active at a time for new creation. Sunset versions will continue to work for existing uses.
    function upgradeModule(Module newModule_) external onlyOwner {
        // Validate new module and get its keycode + version
        (Keycode keycode, uint8 version) = _validateModule(newModule_);

        // Check that the module is installed (latest version will be non-zero)
        Mod storage mod = moduleData[keycode];
        uint8 latest = mod.latestVersion;
        if (latest == uint8(0)) revert ModuleNotInstalled(keycode);

        // Sunset the current version of the module
        mod.versions[latest].sunset = true;

        // Store the new module version
        mod.latestVersion = version;
        mod.versions[version] = Version(newModule_, false);

        // Initialize the new module
        newModule_.INIT();
    }
    

    /// @notice Execute a permissioned function on a module.
    function execOnModule(
        Keycode keycode_,
        bytes memory callData_
    ) external onlyOwner returns (bytes memory) {
        (Module module, ) = _getLatestModuleIfInstalled(keycode_);
        (bool success, bytes memory returnData) = address(module).call(callData_);
        if (!success) revert ModuleExecutionReverted(returnData);
        return returnData;
    }

    // Need to consider the implications of not having upgradable modules and the affect of this list growing over time
    function getModules() external view returns (Keycode[] memory) {
        return modules;
    }

    function _moduleIsInstalled(Keycode keycode_) internal view returns (bool) {
        return moduleData[keycode_].latestVersion != uint8(0);
    }

    function _getLatestModuleIfInstalled(Keycode keycode_) internal view returns (Module, uint8) {
        uint8 latest = moduleData[keycode_].latestVersion;
        if (latest == uint8(0)) revert ModuleNotInstalled(keycode_);
        return (moduleData[keycode_].versions[latest].module, latest);
    }

    function _getSpecificModuleIfInstalled(Keycode keycode_, uint8 version_) internal view returns (Module, uint8) {
        if (version_ == uint8(0)) revert InvalidModule();
        if (version_ > moduleData[keycode_].latestVersion) revert InvalidModule();
        return (moduleData[keycode_].versions[version_].module, version_);
    }

    function _validateModule(Module newModule_) internal view returns (Keycode, uint8) {
        // Validate new module is a contract, has correct parent, and has valid Keycode
        ensureContract(address(newModule_));
        (Keycode keycode, uint8 version) = newModule_.ID();
        ensureValidKeycode(keycode);

        // Validate that the module version is one greater than the latest version
        if (version != moduleData[keycode].latestVersion + 1) revert InvalidModuleUpgrade(keycode, version);

        return (keycode, version);
    }
}

/// @notice Modules are isolated components of a contract that can be upgraded independently.
/// @dev    Two main patterns are considered for Modules:
///         1. Directly calling modules from the parent contract to execute upgradable logic or having the option to add new sub-components to a contract
///         2. Delegate calls to modules to execute upgradable logic, similar to a proxy, but only for specific functions and being able to add new sub-components to a contract
abstract contract Module {
    error Module_OnlyParent(address caller_);
    error Module_InvalidParent();

    /// @notice The parent contract for this module.
    // TODO should we use an Owner pattern here to be able to change the parent?
    // May be useful if the parent contract needs to be replaced.
    // On the otherhand, it may be better to just deploy a new module with the new parent to reduce the governance burden.
    address public parent;

    constructor(address parent_) {
        parent = parent_;
    }

    /// @notice Modifier to restrict functions to be called only by parent module.
    modifier onlyParent() {
        if (msg.sender != parent) revert Module_OnlyParent(msg.sender);
        _;
    }

    /// @notice Module ID: Keycode(5 byte identifier) for the module, 3-5 characters from A-Z and Module version.
    function ID() public pure virtual returns (Keycode, uint8) {}

    /// @notice Initialization function for the module
    /// @dev    This function is called when the module is installed or upgraded by the module.
    /// @dev    MUST BE GATED BY onlyParent. Used to encompass any initialization or upgrade logic.
    function INIT() external virtual onlyParent {}
}