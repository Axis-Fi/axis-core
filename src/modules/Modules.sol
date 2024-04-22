// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {Owned} from "lib/solmate/src/auth/Owned.sol";
import "src/modules/Keycode.sol";

/// @notice    Abstract contract that provides functionality for installing and interacting with modules.
/// @dev       This contract is intended to be inherited by any contract that needs to install modules.
abstract contract WithModules is Owned {
    // ========= ERRORS ========= //

    error InvalidModuleInstall(Keycode keycode_, uint8 version_);
    error ModuleNotInstalled(Keycode keycode_, uint8 version_);
    error ModuleExecutionReverted(bytes error_);
    error ModuleAlreadySunset(Keycode keycode_);
    error ModuleIsSunset(Keycode keycode_);
    error TargetNotAContract(address target_);

    // ========= EVENTS ========= //

    event ModuleInstalled(Keycode indexed keycode, uint8 indexed version, address indexed location);

    event ModuleSunset(Keycode indexed keycode);

    // ========= CONSTRUCTOR ========= //

    constructor(address owner_) Owned(owner_) {}

    // ========= STRUCTS ========= //

    struct ModStatus {
        uint8 latestVersion;
        bool sunset;
    }

    // ========= STATE VARIABLES ========= //

    /// @notice Array of the Keycodes corresponding to the currently installed modules.
    Keycode[] public modules;

    /// @notice The number of modules installed.
    uint256 public modulesCount;

    /// @notice Mapping of Veecode to Module address.
    mapping(Veecode => Module) public getModuleForVeecode;

    /// @notice Mapping of Keycode to module status information.
    mapping(Keycode => ModStatus) public getModuleStatus;

    bool public isExecOnModule;

    // ========= MODULE MANAGEMENT ========= //

    /// @notice     Installs a module. Can be used to install a new module or upgrade an existing one.
    /// @dev        The version of the installed module must be one greater than the latest version. If it's a new module, then the version must be 1.
    /// @dev        Only one version of a module is active for creation functions at a time. Older versions continue to work for existing data.
    /// @dev        If a module is currently sunset, installing a new version will remove the sunset.
    ///
    /// @dev        This function reverts if:
    /// @dev        - The caller is not the owner
    /// @dev        - The module is not a contract
    /// @dev        - The module has an invalid Veecode
    /// @dev        - The module (or other versions) is already installed
    /// @dev        - The module version is not one greater than the latest version
    ///
    /// @param      newModule_  The new module
    function installModule(Module newModule_) external onlyOwner {
        // Validate new module is a contract, has correct parent, and has valid Keycode
        _ensureContract(address(newModule_));
        Veecode veecode = newModule_.VEECODE();
        ensureValidVeecode(veecode);
        (Keycode keycode, uint8 version) = unwrapVeecode(veecode);

        // Validate that the module version is one greater than the latest version
        ModStatus storage status = getModuleStatus[keycode];
        if (version != status.latestVersion + 1) revert InvalidModuleInstall(keycode, version);

        // Store module data and remove sunset if applied
        status.latestVersion = version;
        if (status.sunset) status.sunset = false;
        getModuleForVeecode[veecode] = newModule_;

        // If the module is not already installed, add it to the list of modules
        if (version == uint8(1)) {
            modules.push(keycode);
            modulesCount++;
        }

        // Initialize the module
        newModule_.INIT();

        emit ModuleInstalled(keycode, version, address(newModule_));
    }

    function _ensureContract(address target_) internal view {
        if (target_.code.length == 0) revert TargetNotAContract(target_);
    }

    /// @notice         Sunsets a module
    /// @notice         Sunsetting a module prevents future deployments that use the module, but functionality remains for existing users.
    /// @notice         Modules should implement functionality such that creation functions are disabled if sunset.
    /// @dev            Sunset is used to disable a module type without installing a new one.
    ///
    /// @dev            This function reverts if:
    /// @dev            - The caller is not the owner
    /// @dev            - The module is not installed
    /// @dev            - The module is already sunset
    ///
    /// @param          keycode_    The module keycode
    function sunsetModule(Keycode keycode_) external onlyOwner {
        // Check that the module is installed
        if (!_moduleIsInstalled(keycode_)) revert ModuleNotInstalled(keycode_, 0);

        // Check that the module is not already sunset
        ModStatus storage status = getModuleStatus[keycode_];
        if (status.sunset) revert ModuleAlreadySunset(keycode_);

        // Set the module to sunset
        status.sunset = true;

        emit ModuleSunset(keycode_);
    }

    /// @notice         Checks whether any module is installed under the keycode
    ///
    /// @param          keycode_    The module keycode
    /// @return         True if the module is installed, false otherwise
    function _moduleIsInstalled(Keycode keycode_) internal view returns (bool) {
        // Any module that has been installed will have a latest version greater than 0
        // We can check not equal here to save gas
        return getModuleStatus[keycode_].latestVersion != uint8(0);
    }

    /// @notice         Returns the address of the latest version of a module
    /// @dev            This function reverts if:
    /// @dev            - The module is not installed
    /// @dev            - The module is sunset
    ///
    /// @param          keycode_    The module keycode
    /// @return         The address of the latest version of the module
    function _getLatestModuleIfActive(Keycode keycode_) internal view returns (address) {
        // Check that the module is installed
        ModStatus memory status = getModuleStatus[keycode_];
        if (status.latestVersion == uint8(0)) revert ModuleNotInstalled(keycode_, 0);

        // Check that the module is not sunset
        if (status.sunset) revert ModuleIsSunset(keycode_);

        // Wrap into a Veecode, get module address and return
        // We don't need to check that the Veecode is valid because we already checked that the module is installed and pulled the version from the contract
        Veecode veecode = wrapVeecode(keycode_, status.latestVersion);
        return address(getModuleForVeecode[veecode]);
    }

    /// @notice         Returns the address of a module
    /// @dev            This function reverts if:
    /// @dev            - The specific module and version is not installed
    ///
    /// @param          keycode_    The module keycode
    /// @param          version_    The module version
    /// @return         The address of the module
    function _getModuleIfInstalled(
        Keycode keycode_,
        uint8 version_
    ) internal view returns (address) {
        // Check that the module is installed
        ModStatus memory status = getModuleStatus[keycode_];
        if (status.latestVersion == uint8(0)) revert ModuleNotInstalled(keycode_, 0);

        // Check that the module version is less than or equal to the latest version and greater than 0
        if (version_ > status.latestVersion || version_ == 0) {
            revert ModuleNotInstalled(keycode_, version_);
        }

        // Wrap into a Veecode, get module address and return
        // We don't need to check that the Veecode is valid because we already checked that the module is installed and pulled the version from the contract
        Veecode veecode = wrapVeecode(keycode_, version_);
        return address(getModuleForVeecode[veecode]);
    }

    /// @notice         Returns the address of a module
    /// @dev            This function reverts if:
    /// @dev            - The specific module and version is not installed
    ///
    /// @param          veecode_    The module Veecode
    /// @return         The address of the module
    function _getModuleIfInstalled(Veecode veecode_) internal view returns (address) {
        // In this case, it's simpler to check that the stored address is not zero
        Module mod = getModuleForVeecode[veecode_];
        if (address(mod) == address(0)) {
            (Keycode keycode, uint8 version) = unwrapVeecode(veecode_);
            revert ModuleNotInstalled(keycode, version);
        }
        return address(mod);
    }

    // ========= MODULE FUNCTIONS ========= //

    /// @notice         Performs a call on a module
    /// @notice         This can be used to perform administrative functions on a module, such as setting parameters or calling permissioned functions
    /// @dev            This function reverts if:
    /// @dev            - The caller is not the parent
    /// @dev            - The module is not installed
    /// @dev            - The call is made to a prohibited function
    /// @dev            - The call reverted
    ///
    /// @param          veecode_    The module Veecode
    /// @param          callData_   The call data
    /// @return         The return data from the call
    function execOnModule(
        Veecode veecode_,
        bytes calldata callData_
    ) external onlyOwner returns (bytes memory) {
        // Set the flag to true
        isExecOnModule = true;

        // Check that the module is installed (or revert)
        // Call the module
        (bool success, bytes memory returnData) = _getModuleIfInstalled(veecode_).call(callData_);
        if (!success) revert ModuleExecutionReverted(returnData);

        // Reset the flag to false
        isExecOnModule = false;

        return returnData;
    }
}

/// @notice Modules are isolated components of a contract that can be upgraded independently.
/// @dev    Two main patterns are considered for Modules:
/// @dev    1. Directly calling modules from the parent contract to execute upgradable logic or having the option to add new sub-components to a contract
/// @dev    2. Delegate calls to modules to execute upgradable logic, similar to a proxy, but only for specific functions and being able to add new sub-components to a contract
abstract contract Module {
    // ========= ERRORS ========= //

    /// @notice Error when a module function is called by a non-parent contract
    error Module_OnlyParent(address caller_);

    /// @notice Error when a module function is called by a non-internal contract
    error Module_OnlyInternal();

    /// @notice Error when the parent contract is invalid
    error Module_InvalidParent(address parent_);

    // ========= DATA TYPES ========= //

    /// @notice Enum of module types
    enum Type {
        Auction,
        Derivative,
        Condenser,
        Transformer
    }

    // ========= STATE VARIABLES ========= //

    /// @notice The parent contract for this module.
    address public immutable PARENT;

    // ========= CONSTRUCTOR ========= //

    constructor(address parent_) {
        if (parent_ == address(0)) revert Module_InvalidParent(parent_);

        PARENT = parent_;
    }

    // ========= MODIFIERS ========= //

    /// @notice Modifier to restrict functions to be called only by the parent module.
    modifier onlyParent() {
        if (msg.sender != PARENT) revert Module_OnlyParent(msg.sender);
        _;
    }

    /// @notice Modifier to restrict functions to be called only by internal module.
    /// @notice If a function is called through `execOnModule()` on the parent contract, this modifier will revert.
    /// @dev    This modifier can be used to prevent functions from being called by governance or other external actors through `execOnModule()`.
    modifier onlyInternal() {
        if (msg.sender != PARENT) revert Module_OnlyParent(msg.sender);

        if (WithModules(PARENT).isExecOnModule()) revert Module_OnlyInternal();
        _;
    }

    // ========= FUNCTIONS ========= //

    /// @notice     2 byte identifier for the module type
    /// @dev        This enables the parent contract to check that the module Keycode specified
    /// @dev        is of the correct type
    // solhint-disable-next-line func-name-mixedcase
    function TYPE() public pure virtual returns (Type) {}

    /// @notice 7 byte, versioned identifier for the module. 2 characters from 0-9 that signify the version and 3-5 characters from A-Z.
    // solhint-disable-next-line func-name-mixedcase
    function VEECODE() public pure virtual returns (Veecode) {}

    /// @notice Initialization function for the module
    /// @dev    This function is called when the module is installed or upgraded by the module.
    /// @dev    MUST BE GATED BY onlyParent. Used to encompass any initialization or upgrade logic.
    // solhint-disable-next-line func-name-mixedcase
    function INIT() external virtual onlyParent {}
}
