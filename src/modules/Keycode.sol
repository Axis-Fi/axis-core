// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.19;

// Inspired by Default framework keycode management of dependencies and based on the Modules pattern

/// @notice     5 byte/character identifier for the Module
/// @dev        3-5 characters from A-Z
type Keycode is bytes5;

/// @notice     7 byte identifier for the Module, including version
/// @dev        2 characters from 0-9 (a version number), followed by Keycode
type Veecode is bytes7;

error InvalidVeecode(Veecode veecode_);

function toKeycode(bytes5 keycode_) pure returns (Keycode) {
    return Keycode.wrap(keycode_);
}

function fromKeycode(Keycode keycode_) pure returns (bytes5) {
    return Keycode.unwrap(keycode_);
}

// solhint-disable-next-line func-visibility
function wrapVeecode(Keycode keycode_, uint8 version_) pure returns (Veecode) {
    // Get the digits of the version
    bytes1 firstDigit = bytes1(version_ / 10 + 0x30);
    bytes1 secondDigit = bytes1((version_ % 10) + 0x30);

    // Pack everything and wrap as a Veecode
    return Veecode.wrap(bytes7(abi.encodePacked(firstDigit, secondDigit, keycode_)));
}

// solhint-disable-next-line func-visibility
function toVeecode(bytes7 veecode_) pure returns (Veecode) {
    return Veecode.wrap(veecode_);
}

// solhint-disable-next-line func-visibility
function fromVeecode(Veecode veecode_) pure returns (bytes7) {
    return Veecode.unwrap(veecode_);
}

function unwrapVeecode(Veecode veecode_) pure returns (Keycode, uint8) {
    bytes7 unwrapped = Veecode.unwrap(veecode_);

    // Get the version from the first 2 bytes
    if (unwrapped[0] < 0x30 || unwrapped[0] > 0x39 || unwrapped[1] < 0x30 || unwrapped[1] > 0x39) {
        revert InvalidVeecode(veecode_);
    }
    uint8 version = (uint8(unwrapped[0]) - 0x30) * 10;
    version += uint8(unwrapped[1]) - 0x30;

    // Get the Keycode by shifting the full Veecode to the left by 2 bytes
    Keycode keycode = Keycode.wrap(bytes5(unwrapped << 16));

    return (keycode, version);
}

function keycodeFromVeecode(Veecode veecode_) pure returns (Keycode) {
    (Keycode keycode,) = unwrapVeecode(veecode_);
    return keycode;
}

// solhint-disable-next-line func-visibility
function ensureValidVeecode(Veecode veecode_) pure {
    bytes7 unwrapped = Veecode.unwrap(veecode_);
    for (uint256 i; i < 7;) {
        bytes1 char = unwrapped[i];
        if (i < 2) {
            // First 2 characters must be the version, each character is a number 0-9
            if (char < 0x30 || char > 0x39) revert InvalidVeecode(veecode_);
        } else if (i < 5) {
            // Next 3 characters after the first 3 can be A-Z
            if (char < 0x41 || char > 0x5A) revert InvalidVeecode(veecode_);
        } else {
            // Last 2 character must be A-Z or blank
            if (char != 0x00 && (char < 0x41 || char > 0x5A)) revert InvalidVeecode(veecode_);
        }
        unchecked {
            i++;
        }
    }

    // Check that the version is not 0
    // This is because the version is by default 0 if the module is not installed
    (, uint8 moduleVersion) = unwrapVeecode(veecode_);
    if (moduleVersion == 0) revert InvalidVeecode(veecode_);
}
