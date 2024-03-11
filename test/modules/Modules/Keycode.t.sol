// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {
    Keycode,
    toKeycode,
    fromKeycode,
    Veecode,
    wrapVeecode,
    fromVeecode,
    unwrapVeecode,
    ensureValidVeecode,
    InvalidVeecode
} from "src/modules/Modules.sol";

contract KeycodeTest is Test {
    function test_keycode() external {
        Keycode keycode = toKeycode("TEST");
        assertEq(fromKeycode(keycode), "TEST");
    }

    function test_ensureValidVeecode_singleDigitNumber() external {
        Keycode keycode = toKeycode("TEST");
        Veecode t1Veecode = wrapVeecode(keycode, 1);

        ensureValidVeecode(t1Veecode);
    }

    function test_ensureValidVeecode_doubleDigitNumber() external {
        Keycode keycode = toKeycode("TEST");
        Veecode t1Veecode = wrapVeecode(keycode, 11);

        ensureValidVeecode(t1Veecode);
    }

    function _modifyKeycode(
        bytes5 keycode_,
        uint8 index_,
        uint8 character_
    ) internal pure returns (bytes5) {
        bytes memory keycodeBytes = abi.encodePacked(keycode_);
        keycodeBytes[index_] = bytes1(character_);
        return bytes5(keycodeBytes);
    }

    function test_ensureValidVeecode_length() external {
        Keycode t1Keycode = toKeycode("TES");
        Veecode t1Veecode = wrapVeecode(t1Keycode, 11);
        ensureValidVeecode(t1Veecode);

        Keycode t2Keycode = toKeycode("TEST");
        Veecode t2Veecode = wrapVeecode(t2Keycode, 11);
        ensureValidVeecode(t2Veecode);
        assertFalse(fromVeecode(t1Veecode) == fromVeecode(t2Veecode));

        Keycode t3Keycode = toKeycode("TESTT");
        Veecode t3Veecode = wrapVeecode(t3Keycode, 21);
        ensureValidVeecode(t3Veecode);
        assertFalse(fromVeecode(t2Veecode) == fromVeecode(t3Veecode));

        Keycode t4Keycode = toKeycode("TESTT");
        Veecode t4Veecode = wrapVeecode(t4Keycode, 1);
        ensureValidVeecode(t4Veecode);
        assertFalse(fromVeecode(t3Veecode) == fromVeecode(t4Veecode));
    }

    function testRevert_ensureValidVeecode_invalidRequiredCharacter(
        uint8 character_,
        uint8 index_
    ) external {
        // Only manipulating the first 3 characters
        vm.assume(index_ < 3);

        // Restrict the character to outside of A-Z
        vm.assume(!(character_ >= 65 && character_ <= 90));

        // Replace the fuzzed character
        bytes5 keycodeInput = _modifyKeycode("TST", index_, character_);

        Keycode keycode = toKeycode(keycodeInput);
        Veecode t1Veecode = wrapVeecode(keycode, 1);

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, t1Veecode);
        vm.expectRevert(err);

        ensureValidVeecode(t1Veecode);
    }

    function testRevert_ensureValidVeecode_invalidOptionalCharacter(
        uint8 character_,
        uint8 index_
    ) external {
        // Only manipulating the characters 4-5
        vm.assume(index_ < 3);

        // Restrict the character to outside of A-Z and blank
        vm.assume(!(character_ >= 65 && character_ <= 90) && character_ != 0);

        // Replace the fuzzed character
        bytes5 keycodeInput = _modifyKeycode("TST", index_, character_);

        Keycode keycode = toKeycode(keycodeInput);
        Veecode t1Veecode = wrapVeecode(keycode, 1);

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, t1Veecode);
        vm.expectRevert(err);

        ensureValidVeecode(t1Veecode);
    }

    function testRevert_ensureValidVeecode_zeroVersion() external {
        Keycode keycode = toKeycode("TEST");
        Veecode t1Veecode = wrapVeecode(keycode, 0);

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, t1Veecode);
        vm.expectRevert(err);

        ensureValidVeecode(t1Veecode);
    }

    function testRevert_ensureValidVeecode_invalidVersion(uint8 version_) external {
        // Restrict the version to outside of 0-99
        vm.assume(!(version_ >= 0 && version_ <= 99));

        Keycode keycode = toKeycode("TEST");
        Veecode t1Veecode = wrapVeecode(keycode, version_);

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, t1Veecode);
        vm.expectRevert(err);

        ensureValidVeecode(t1Veecode);
    }

    function test_unwrapVeecode() external {
        Keycode keycode = toKeycode("TEST");
        Veecode t1Veecode = wrapVeecode(keycode, 1);
        (Keycode keycode_, uint8 moduleVersion_) = unwrapVeecode(t1Veecode);
        assertEq(fromKeycode(keycode_), "TEST");
        assertEq(moduleVersion_, 1);

        Veecode t2Veecode = wrapVeecode(keycode, 11);
        (keycode_, moduleVersion_) = unwrapVeecode(t2Veecode);
        assertEq(moduleVersion_, 11);

        Veecode t3Veecode = wrapVeecode(keycode, 99);
        (keycode_, moduleVersion_) = unwrapVeecode(t3Veecode);
        assertEq(moduleVersion_, 99);

        Veecode t4Veecode = wrapVeecode(keycode, 0);
        (keycode_, moduleVersion_) = unwrapVeecode(t4Veecode);
        assertEq(moduleVersion_, 0);

        Veecode t5Veecode = wrapVeecode(toKeycode("TES"), 11);
        (keycode_, moduleVersion_) = unwrapVeecode(t5Veecode);
        assertEq(fromKeycode(keycode_), "TES");

        Veecode t6Veecode = wrapVeecode(toKeycode("TESTT"), 11);
        (keycode_, moduleVersion_) = unwrapVeecode(t6Veecode);
        assertEq(fromKeycode(keycode_), "TESTT");
    }
}
