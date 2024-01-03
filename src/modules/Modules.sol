/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Owned} from "lib/solmate/src/auth/Owned.sol";

// Inspired by Default framework keycode management of dependencies and based on the Modules pattern

// Keycode functions

/// @notice     5 byte/character identifier for the Module
/// @dev        3-5 characters from A-Z
type ModuleKeycode is bytes5;

/// @notice     7 byte identifier for the Module, including version
/// @dev        ModuleKeycode, followed by 2 characters from 0-9
type Keycode is bytes7;

error TargetNotAContract(address target_);
error InvalidKeycode(Keycode keycode_);

function toModuleKeycode(bytes5 moduleKeycode_) pure returns (ModuleKeycode) {
    return ModuleKeycode.wrap(moduleKeycode_);
}

function fromModuleKeycode(ModuleKeycode moduleKeycode_) pure returns (bytes5) {
    return ModuleKeycode.unwrap(moduleKeycode_);
}

// solhint-disable-next-line func-visibility
function toKeycode(ModuleKeycode moduleKeycode_, uint8 version_) pure returns (Keycode) {
    bytes5 moduleKeycodeBytes = fromModuleKeycode(moduleKeycode_);
    bytes memory keycodeBytes = new bytes(7);

    // Copy moduleKeycode_ into keycodeBytes
    for (uint256 i; i < 5; i++) {
        keycodeBytes[i] = moduleKeycodeBytes[i];
    }

    // Get the digits of the version
    uint8 firstDigit = version_ / 10;
    uint8 secondDigit = version_ % 10;

    // Convert the digits to bytes
    keycodeBytes[5] = bytes1(firstDigit + 0x30);
    keycodeBytes[6] = bytes1(secondDigit + 0x30);

    return Keycode.wrap(bytes7(keycodeBytes));
}

// solhint-disable-next-line func-visibility
function fromKeycode(Keycode keycode_) pure returns (bytes7) {
    return Keycode.unwrap(keycode_);
}

function versionFromKeycode(Keycode keycode_) pure returns (uint8) {
    bytes7 unwrapped = Keycode.unwrap(keycode_);
    uint8 firstDigit = uint8(unwrapped[5]) - 0x30;
    uint8 secondDigit = uint8(unwrapped[6]) - 0x30;
    return firstDigit * 10 + secondDigit;
}

function moduleFromKeycode(Keycode keycode_) pure returns (ModuleKeycode) {
    bytes7 unwrapped = Keycode.unwrap(keycode_);
    return ModuleKeycode.wrap(bytes5(unwrapped));
}

// solhint-disable-next-line func-visibility
function ensureContract(address target_) view {
    if (target_.code.length == 0) revert TargetNotAContract(target_);
}

// solhint-disable-next-line func-visibility
function ensureValidKeycode(Keycode keycode_) pure {
    bytes7 unwrapped = Keycode.unwrap(keycode_);
    for (uint256 i; i < 7; ) {
        bytes1 char = unwrapped[i];
        if (i < 3) {
            // First 3 characters must be A-Z
            if (char < 0x41 || char > 0x5A) revert InvalidKeycode(keycode_);
        } else if (i < 5) {
            // Next 2 characters after the first 3 can be A-Z or blank, 0-9, or .
            if (char != 0x00 && (char < 0x41 || char > 0x5A) && (char < 0x30 || char > 0x39)) revert InvalidKeycode(keycode_);
        } else {
            // Last 2 character must be 0-9
            if (char < 0x30 || char > 0x39) revert InvalidKeycode(keycode_);
        }
        unchecked {
            i++;
        }
    }

    // Check that the version is not 0
    // This is because the version is by default 0 if the module is not installed
    if (versionFromKeycode(keycode_) == 0) revert InvalidKeycode(keycode_);
}

abstract contract WithModules is Owned {
    // ========= ERRORS ========= //
    error InvalidModule();
    error InvalidModuleUpgrade(Keycode keycode_);
    error ModuleAlreadyInstalled(ModuleKeycode moduleKeycode_, uint8 version_);
    error ModuleNotInstalled(ModuleKeycode moduleKeycode_, uint8 version_);
    error ModuleExecutionReverted(bytes error_);
    error ModuleAlreadySunset(Keycode keycode_);

    // ========= EVENTS ========= //

    event ModuleInstalled(ModuleKeycode indexed moduleKeycode_, uint8 indexed version_, address indexed address_);

    event ModuleUpgraded(ModuleKeycode indexed moduleKeycode_, uint8 indexed version_, address indexed address_);

    // ========= CONSTRUCTOR ========= //

    constructor(address owner_) Owned(owner_) {}

    // ========= MODULE MANAGEMENT ========= //

    /// @notice Array of all modules currently installed.
    Keycode[] public modules;

    /// @notice Mapping of Keycode to Module address.
    mapping(Keycode => Module) public getModuleForKeycode;

    /// @notice Mapping of ModuleKeycode to latest version.
    mapping(ModuleKeycode => uint8) public getModuleLatestVersion;

    /// @notice Mapping of Keycode to whether the module is sunset.
    mapping(Keycode => bool) public moduleSunset;

    /// @notice     Installs a new module
    /// @notice     Subsequent versions should be installed via upgradeModule
    /// @dev        This function performs the following:
    /// @dev        - Validates the new module
    /// @dev        - Checks that the module (or other versions) is not already installed
    /// @dev        - Stores the module details
    ///
    /// @dev        This function reverts if:
    /// @dev        - The caller is not the owner
    /// @dev        - The module is not a contract
    /// @dev        - The module has an invalid Keycode
    /// @dev        - The module (or other versions) is already installed
    ///
    /// @param newModule_  The new module
    function installModule(Module newModule_) external onlyOwner {
        // Validate new module and get its keycode
        Keycode keycode = _validateModule(newModule_);
        ModuleKeycode moduleKeycode = moduleFromKeycode(keycode);
        uint8 moduleVersion = versionFromKeycode(keycode);

        // Check that the module is not already installed
        // If this reverts, then the new module should be installed via upgradeModule
        uint8 moduleInstalledVersion = getModuleLatestVersion[moduleKeycode];
        if (moduleInstalledVersion > 0)
            revert ModuleAlreadyInstalled(moduleKeycode, moduleInstalledVersion);

        // Store module in module
        getModuleForKeycode[keycode] = newModule_;
        modules.push(keycode);

        // Update latest version
        getModuleLatestVersion[moduleKeycode] = moduleVersion;

        // Initialize the module
        newModule_.INIT();

        emit ModuleInstalled(moduleKeycode, moduleVersion, address(newModule_));
    }

    /// @notice Prevents future use of module, but functionality remains for existing users. Modules should implement functionality such that creation functions are disabled if sunset.
    function sunsetModule(Keycode keycode_) external onlyOwner {
        // Check that the module is installed
        ModuleKeycode moduleKeycode_ = moduleFromKeycode(keycode_);
        uint8 moduleVersion_ = versionFromKeycode(keycode_);
        if (!_moduleIsInstalled(keycode_)) revert ModuleNotInstalled(moduleKeycode_, moduleVersion_);

        // Check that the module is not already sunset
        if (moduleSunset[keycode_]) revert ModuleAlreadySunset(keycode_);

        // Set the module to sunset
        moduleSunset[keycode_] = true;
    }

    /// @notice     Upgrades an existing module
    /// @dev        This function performs the following:
    /// @dev        - Validates the new module
    /// @dev        - Checks that a prior version of the module is already installed
    /// @dev        - Stores the module details
    /// @dev        - Marks the previous version as sunset
    ///
    /// @dev        This function reverts if:
    /// @dev        - The caller is not the owner
    /// @dev        - The module is not a contract
    /// @dev        - The module has an invalid Keycode
    /// @dev        - The module is not already installed
    /// @dev        - The same or newer module version is already installed
    function upgradeModule(Module newModule_) external onlyOwner {
        // Validate new module and get its keycode
        Keycode keycode = _validateModule(newModule_);

        // Check that an earlier version of the module is installed
        // If this reverts, then the new module should be installed via installModule
        ModuleKeycode moduleKeycode = moduleFromKeycode(keycode);
        uint8 moduleVersion = versionFromKeycode(keycode);
        uint8 moduleInstalledVersion = getModuleLatestVersion[moduleKeycode];
        if (moduleInstalledVersion == 0)
            revert ModuleNotInstalled(moduleKeycode, moduleInstalledVersion);

        if (moduleInstalledVersion >= moduleVersion)
            revert ModuleAlreadyInstalled(moduleKeycode, moduleInstalledVersion);

        // Update module records
        getModuleForKeycode[keycode] = newModule_;
        modules.push(keycode);

        // Update latest version
        getModuleLatestVersion[moduleKeycode] = moduleVersion;

        // Sunset the previous version
        Keycode previousKeycode = toKeycode(moduleKeycode, moduleInstalledVersion);
        moduleSunset[previousKeycode] = true;

        // Initialize the module
        newModule_.INIT();

        emit ModuleUpgraded(moduleKeycode, moduleVersion, address(newModule_));
    }

    // Decide if we need this function, i.e. do we need to set any parameters or call permissioned functions on any modules?
    // Answer: yes, e.g. when setting default values on an Auction module, like minimum duration or minimum deposit interval
    function execOnModule(
        Keycode keycode_,
        bytes memory callData_
    ) external onlyOwner returns (bytes memory) {
        address module = _getModuleIfInstalled(keycode_);
        (bool success, bytes memory returnData) = module.call(callData_);
        if (!success) revert ModuleExecutionReverted(returnData);
        return returnData;
    }

    // Need to consider the implications of not having upgradable modules and the affect of this list growing over time
    function getModules() external view returns (Keycode[] memory) {
        return modules;
    }

    function _moduleIsInstalled(Keycode keycode_) internal view returns (bool) {
        Module module = getModuleForKeycode[keycode_];
        return address(module) != address(0);
    }

    function _getModuleIfInstalled(Keycode keycode_) internal view returns (address) {
        Module module = getModuleForKeycode[keycode_];
        ModuleKeycode moduleKeycode_ = moduleFromKeycode(keycode_);
        uint8 moduleVersion_ = versionFromKeycode(keycode_);
        if (address(module) == address(0)) revert ModuleNotInstalled(moduleKeycode_, moduleVersion_);
        return address(module);
    }

    function _validateModule(Module newModule_) internal view returns (Keycode) {
        // Validate new module is a contract, has correct parent, and has valid Keycode
        ensureContract(address(newModule_));
        Keycode keycode = newModule_.KEYCODE();
        ensureValidKeycode(keycode);

        return keycode;
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

    /// @notice 5 byte identifier for the module. 3-5 characters from A-Z.
    function KEYCODE() public pure virtual returns (Keycode) {}

    /// @notice Initialization function for the module
    /// @dev    This function is called when the module is installed or upgraded by the module.
    /// @dev    MUST BE GATED BY onlyParent. Used to encompass any initialization or upgrade logic.
    function INIT() external virtual onlyParent {}
}

// TODO handle version number
