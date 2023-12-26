/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Owned} from "lib/solmate/src/auth/Owned.sol";

// Inspired by Default framework keycode management of dependencies and based on the Modules pattern

// Keycode functions

// Type VersionedKeycode: 5 byte characters, 1 bytes for versions
// Descendent contracts will need to store the versioned keycode
// WithModules will track the versions of the modules installed

/// @notice     5 byte/character identifier for the Module
/// @dev        3-5 characters from A-Z
type ModuleKeycode is bytes5;

/// @notice     6 byte identifier for the Module, including version
/// @dev        ModuleKeycode, followed by 1 byte for version
type Keycode is bytes6;

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
    return Keycode.wrap(bytes6(abi.encode(moduleKeycode_, version_)));
}

// solhint-disable-next-line func-visibility
function fromKeycode(Keycode keycode_) pure returns (ModuleKeycode, uint8) {
    bytes6 unwrappedKeycode = Keycode.unwrap(keycode_);
    bytes memory keycodeBytes = new bytes(6);
    for (uint256 i; i < 6; i++) {
        keycodeBytes[i] = unwrappedKeycode[i];
    }

    return abi.decode(keycodeBytes, (ModuleKeycode, uint8));
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
            // Characters after the first 3 can be A-Z, blank, 0-9, or .
            if (char != 0x00 && (char < 0x41 || char > 0x5A) && (char < 0x30 || char > 0x39) && char != 0x2E) revert InvalidKeycode(keycode_);
        }
        unchecked {
            i++;
        }
    }
}


abstract contract WithModules is Owned {
    // ========= ERRORS ========= //
    error InvalidModule();
    error InvalidModuleUpgrade(Keycode keycode_);
    error ModuleAlreadyInstalled(Keycode keycode_);
    error ModuleNotInstalled(Keycode keycode_);
    error ModuleExecutionReverted(bytes error_);
    error ModuleAlreadySunset(Keycode keycode_);

    // ========= CONSTRUCTOR ========= //

    constructor(address owner_) Owned(owner_) {}

    // ========= MODULE MANAGEMENT ========= //

    /// @notice Array of all modules currently installed.
    Keycode[] public modules;

    /// @notice Mapping of Keycode to Module address.
    mapping(Keycode => Module) public getModuleForKeycode;

    /// @notice Mapping of Keycode to whether the module is sunset.
    mapping(Keycode => bool) public moduleSunset;

    function installModule(Module newModule_) external onlyOwner {
        // Validate new module and get its subkeycode
        Keycode keycode = _validateModule(newModule_);

        // Check that a module with this keycode is not already installed
        // If this reverts, then the new module should be installed via upgradeModule
        if (address(getModuleForKeycode[keycode]) != address(0))
            revert ModuleAlreadyInstalled(keycode);

        // Store module in module
        getModuleForKeycode[keycode] = newModule_;
        modules.push(keycode);

        // Initialize the module
        newModule_.INIT();
    }

    /// @notice Prevents future use of module, but functionality remains for existing users. Modules should implement functionality such that creation functions are disabled if sunset.
    function sunsetModule(Keycode keycode_) external onlyOwner {
        // Check that the module is installed
        if (!_moduleIsInstalled(keycode_)) revert ModuleNotInstalled(keycode_);

        // Check that the module is not already sunset
        if (moduleSunset[keycode_]) revert ModuleAlreadySunset(keycode_);

        // Set the module to sunset
        moduleSunset[keycode_] = true;
    }


    // TODO may need to use proxies instead of this design to allow for upgrading due to a bug and keeping collateral in a derivative contract
    // The downside is that you have the additional gas costs and potential for exploits in OCG
    // It may be better to just not have the modules be upgradable
    // Having a shutdown mechanism for a specific module and an entire auctionhouse version might be good as well.
    // Though it would still need to allow for claiming of outstanding derivative tokens.

    // NOTE: don't use upgradable modules. simply require a new module to be installed and sunset the old one to migrate functionality.
    // This doesn't allow fixing a contract for existing users / data, but it prevents malicious upgrades.
    // Versions can be used in the keycode to denote a new version of the same module, e.g. SDA v1.1
    // function upgradeModule(Module newModule_) external onlyOwner {
    //     // Validate new module and get its keycode
    //     Keycode keycode = _validateModule(newModule_);

    //     // Get the existing module, ensure that it's not zero and not the same as the new module
    //     // If this reverts due to no module being installed, then the new module should be installed via installModule
    //     Module oldModule = getModuleForKeycode[keycode];
    //     if (oldModule == Module(address(0)) || oldModule == newModule_)
    //         revert InvalidModuleUpgrade(keycode);

    //     // Update module in module
    //     getModuleForKeycode[keycode] = newModule_;

    //     // Initialize the module
    //     newModule_.INIT();
    // }

    // Decide if we need this function, i.e. do we need to set any parameters or call permissioned functions on any modules?
    // Answer: yes, e.g. when setting default values on an Auction module, like minimum duration or minimum deposit interval
    function execOnModule(
        Keycode keycode_,
        bytes memory callData_
    ) external onlyOwner returns (bytes memory) {
        Module module = _getModuleIfInstalled(keycode_);
        (bool success, bytes memory returnData) = address(module).call(callData_);
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

    function _getModuleIfInstalled(Keycode keycode_) internal view returns (Module) {
        Module module = getModuleForKeycode[keycode_];
        if (address(module) == address(0)) revert ModuleNotInstalled(keycode_);
        return module;
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