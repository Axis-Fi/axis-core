// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

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
        Veecode t1_veecode = wrapVeecode(keycode, 1);

        ensureValidVeecode(t1_veecode);
    }

    function test_ensureValidVeecode_doubleDigitNumber() external {
        Keycode keycode = toKeycode("TEST");
        Veecode t1_veecode = wrapVeecode(keycode, 11);

        ensureValidVeecode(t1_veecode);
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
        Keycode t1_keycode = toKeycode("TES");
        Veecode t1_veecode = wrapVeecode(t1_keycode, 11);
        ensureValidVeecode(t1_veecode);

        Keycode t2_keycode = toKeycode("TEST");
        Veecode t2_veecode = wrapVeecode(t2_keycode, 11);
        ensureValidVeecode(t2_veecode);
        assertFalse(fromVeecode(t1_veecode) == fromVeecode(t2_veecode));

        Keycode t3_keycode = toKeycode("TESTT");
        Veecode t3_veecode = wrapVeecode(t3_keycode, 21);
        ensureValidVeecode(t3_veecode);
        assertFalse(fromVeecode(t2_veecode) == fromVeecode(t3_veecode));

        Keycode t4_keycode = toKeycode("TESTT");
        Veecode t4_veecode = wrapVeecode(t4_keycode, 1);
        ensureValidVeecode(t4_veecode);
        assertFalse(fromVeecode(t3_veecode) == fromVeecode(t4_veecode));
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
        Veecode t1_veecode = wrapVeecode(keycode, 1);

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, t1_veecode);
        vm.expectRevert(err);

        ensureValidVeecode(t1_veecode);
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
        Veecode t1_veecode = wrapVeecode(keycode, 1);

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, t1_veecode);
        vm.expectRevert(err);

        ensureValidVeecode(t1_veecode);
    }

    function testRevert_ensureValidVeecode_zeroVersion() external {
        Keycode keycode = toKeycode("TEST");
        Veecode t1_veecode = wrapVeecode(keycode, 0);

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, t1_veecode);
        vm.expectRevert(err);

        ensureValidVeecode(t1_veecode);
    }

    function testRevert_ensureValidVeecode_invalidVersion(uint8 version_) external {
        // Restrict the version to outside of 0-99
        vm.assume(!(version_ >= 0 && version_ <= 99));

        Keycode keycode = toKeycode("TEST");
        Veecode t1_veecode = wrapVeecode(keycode, version_);

        bytes memory err = abi.encodeWithSelector(InvalidVeecode.selector, t1_veecode);
        vm.expectRevert(err);

        ensureValidVeecode(t1_veecode);
    }

    function test_unwrapVeecode() external {
        Keycode keycode = toKeycode("TEST");
        Veecode t1_veecode = wrapVeecode(keycode, 1);
        (Keycode keycode_, uint8 moduleVersion_) = unwrapVeecode(t1_veecode);
        assertEq(fromKeycode(keycode_), "TEST");
        assertEq(moduleVersion_, 1);

        Veecode t2_veecode = wrapVeecode(keycode, 11);
        (keycode_, moduleVersion_) = unwrapVeecode(t2_veecode);
        assertEq(moduleVersion_, 11);

        Veecode t3_veecode = wrapVeecode(keycode, 99);
        (keycode_, moduleVersion_) = unwrapVeecode(t3_veecode);
        assertEq(moduleVersion_, 99);

        Veecode t4_veecode = wrapVeecode(keycode, 0);
        (keycode_, moduleVersion_) = unwrapVeecode(t4_veecode);
        assertEq(moduleVersion_, 0);

        Veecode t5_veecode = wrapVeecode(toKeycode("TES"), 11);
        (keycode_, moduleVersion_) = unwrapVeecode(t5_veecode);
        assertEq(fromKeycode(keycode_), "TES");

        Veecode t6_veecode = wrapVeecode(toKeycode("TESTT"), 11);
        (keycode_, moduleVersion_) = unwrapVeecode(t6_veecode);
        assertEq(fromKeycode(keycode_), "TESTT");
    }
}
