// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ModuleKeycode, toModuleKeycode, fromModuleKeycode, Keycode, toKeycode, fromKeycode, ensureValidKeycode, InvalidKeycode} from "src/modules/Modules.sol";

contract KeycodeTest is Test {
    function test_moduleKeycode() external {
        ModuleKeycode moduleKeycode = toModuleKeycode("TEST");
        assertEq(fromModuleKeycode(moduleKeycode), "TEST");
    }

    function test_ensureValidKeycode_singleDigitNumber() external {
        ModuleKeycode moduleKeycode = toModuleKeycode("TEST");
        Keycode t1_keycode = toKeycode(moduleKeycode, 1);

        bytes7 unwrapped = Keycode.unwrap(t1_keycode);
        console2.logBytes1(unwrapped[5]);
        console2.logBytes1(unwrapped[6]);

        ensureValidKeycode(t1_keycode);
    }

    function test_ensureValidKeycode_doubleDigitNumber() external {
        ModuleKeycode moduleKeycode = toModuleKeycode("TEST");
        Keycode t1_keycode = toKeycode(moduleKeycode, 11);

        ensureValidKeycode(t1_keycode);
    }

    function _modifyModuleKeycode(bytes5 moduleKeycode_, uint8 index_, uint8 character_) internal pure returns (bytes5) {
        bytes memory moduleKeycodeBytes = abi.encodePacked(moduleKeycode_);
        moduleKeycodeBytes[index_] = bytes1(character_);
        return bytes5(moduleKeycodeBytes);
    }

    function test_ensureValidKeycode_length() external {
        ModuleKeycode t1_moduleKeycode = toModuleKeycode("TES");
        Keycode t1_keycode = toKeycode(t1_moduleKeycode, 11);
        ensureValidKeycode(t1_keycode);

        ModuleKeycode t2_moduleKeycode = toModuleKeycode("TEST");
        Keycode t2_keycode = toKeycode(t2_moduleKeycode, 11);
        ensureValidKeycode(t2_keycode);
        assertFalse(fromKeycode(t1_keycode) == fromKeycode(t2_keycode));

        ModuleKeycode t3_moduleKeycode = toModuleKeycode("TESTT");
        Keycode t3_keycode = toKeycode(t3_moduleKeycode, 21);
        ensureValidKeycode(t3_keycode);
        assertFalse(fromKeycode(t2_keycode) == fromKeycode(t3_keycode));

        ModuleKeycode t4_moduleKeycode = toModuleKeycode("TESTT");
        Keycode t4_keycode = toKeycode(t4_moduleKeycode, 1);
        ensureValidKeycode(t4_keycode);
        assertFalse(fromKeycode(t3_keycode) == fromKeycode(t4_keycode));
    }

    function testRevert_ensureValidKeycode_invalidRequiredCharacter(uint8 character_, uint8 index_) external {
        // Only manipulating the first 3 characters
        vm.assume(index_ < 3);

        // Restrict the character to outside of A-Z
        vm.assume(!(character_ >= 65 && character_ <= 90));

        // Replace the fuzzed character
        bytes5 moduleKeycodeInput = _modifyModuleKeycode("TST", index_, character_);

        ModuleKeycode moduleKeycode = toModuleKeycode(moduleKeycodeInput);
        Keycode t1_keycode = toKeycode(moduleKeycode, 1);

        bytes memory err = abi.encodeWithSelector(
            InvalidKeycode.selector,
            t1_keycode
        );
        vm.expectRevert(err);

        ensureValidKeycode(t1_keycode);
    }

    function testRevert_ensureValidKeycode_invalidOptionalCharacter(uint8 character_, uint8 index_) external {
        // Only manipulating the characters 4-5
        vm.assume(index_ < 3);

        // Restrict the character to outside of A-Z and blank
        vm.assume(!(character_ >= 65 && character_ <= 90) && character_ != 0);

        // Replace the fuzzed character
        bytes5 moduleKeycodeInput = _modifyModuleKeycode("TST", index_, character_);

        ModuleKeycode moduleKeycode = toModuleKeycode(moduleKeycodeInput);
        Keycode t1_keycode = toKeycode(moduleKeycode, 1);

        bytes memory err = abi.encodeWithSelector(
            InvalidKeycode.selector,
            t1_keycode
        );
        vm.expectRevert(err);

        ensureValidKeycode(t1_keycode);
    }

    function testRevert_ensureValidKeycode_invalidVersion(uint8 version_) external {
        // Restrict the version to outside of 0-99
        vm.assume(!(version_ >= 0 && version_ <= 99));

        ModuleKeycode moduleKeycode = toModuleKeycode("TEST");
        Keycode t1_keycode = toKeycode(moduleKeycode, version_);

        bytes memory err = abi.encodeWithSelector(
            InvalidKeycode.selector,
            t1_keycode
        );
        vm.expectRevert(err);

        ensureValidKeycode(t1_keycode);
    }
}
