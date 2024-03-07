// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Testing Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ECIESFFITest} from "./ECIES_FFI.sol";

// ECIES
import {Point, ECIES} from "src/lib/ECIES.sol";

contract ECIESEncryptTest is Test {
    // [X] when the public key is invalid
    //      [X] it reverts
    // [X] when the private key is greater than or equal to the group order
    //      [X] it reverts
    // [X] when the private key is zero
    //      [X] it reverts
    // [X] it encrypts the message and provides the message pub key

    function setUp() external {}

    function testRevert_invalidPubKey() public {
        // Setup encryption parameters
        uint256 message = 1;
        Point memory recipientPubKey = Point(1, 1);
        uint256 privateKey = 1;
        uint256 salt = 1;

        // Attempt to encrypt with an invalid public key, expect revert
        bytes memory err = abi.encodePacked("Invalid public key.");
        vm.expectRevert(err);
        ECIES.encrypt(message, recipientPubKey, privateKey, salt);
    }

    function testRevert_privateKeyTooLarge(uint256 privateKey_) public {
        vm.assume(privateKey_ >= ECIES.GROUP_ORDER);

        // Setup encryption parameters
        uint256 message = 1;
        Point memory recipientPubKey = Point(1, 2);
        uint256 salt = 1;

        // Attempt to encrypt with a private key that is too large, expect revert
        bytes memory err = abi.encodePacked("Invalid private key.");
        vm.expectRevert(err);
        ECIES.encrypt(message, recipientPubKey, privateKey_, salt);
    }

    function testRevert_privateKeyZero() public {
        // Setup encryption parameters
        uint256 message = 1;
        Point memory recipientPubKey = Point(1, 2);
        uint256 privateKey = 0;
        uint256 salt = 1;

        // Attempt to encrypt with a private key that is zero, expect revert
        bytes memory err = abi.encodePacked("Invalid private key.");
        vm.expectRevert(err);
        ECIES.encrypt(message, recipientPubKey, privateKey, salt);
    }

    function test_encrypt() public {
        // Setup encryption parameters
        uint256 message = 1;
        Point memory recipientPubKey = ECIES.calcPubKey(Point(1, 2), 2);
        uint256 messagePrivateKey = 3;
        uint256 salt = 1;

        // Encrypt the message
        (uint256 ciphertext, Point memory ciphertextPubKey) =
            ECIES.encrypt(message, recipientPubKey, messagePrivateKey, salt);

        // Confirm it matches the expected value
        assertEq(
            ciphertext, uint256(0xf96d7675ae04b89c9b5a9b0613d3530bb939186d05959efba9b3249a461abbc4)
        );
        assertEq(
            ciphertextPubKey.x,
            uint256(0x0769bf9ac56bea3ff40232bcb1b6bd159315d84715b8e679f2d355961915abf0)
        );
        assertEq(
            ciphertextPubKey.y,
            uint256(0x2ab799bee0489429554fdb7c8d086475319e63b40b9c5b57cdf1ff3dd9fe2261)
        );
    }

    function testFuzz_encrypt(
        uint256 message_,
        uint256 salt_,
        uint256 recipientPrivKey_,
        uint256 messagePrivKey_
    ) public {
        vm.assume(recipientPrivKey_ > 0 && recipientPrivKey_ < ECIES.GROUP_ORDER);
        vm.assume(messagePrivKey_ > 0 && messagePrivKey_ < ECIES.GROUP_ORDER);

        // Calculate public key from recipient private key
        Point memory recipientPubKey = ECIES.calcPubKey(Point(1, 2), recipientPrivKey_);

        // Encrypt the message
        (uint256 ciphertext, Point memory ciphertextPubKey) =
            ECIES.encrypt(message_, recipientPubKey, messagePrivKey_, salt_);

        // Confirm it matches the expected value
        assertEq(
            ciphertext,
            message_
                ^ ECIES.deriveSymmetricKey(ECIES.calcPubKey(recipientPubKey, messagePrivKey_).x, salt_)
        );
        Point memory expectedPubKey = ECIES.calcPubKey(Point(1, 2), messagePrivKey_);
        assertEq(ciphertextPubKey.x, expectedPubKey.x);
        assertEq(ciphertextPubKey.y, expectedPubKey.y);
    }

    function testFuzz_encrypt_gas(
        uint256 message_,
        uint256 recipientPrivKey_,
        uint256 messagePrivKey_,
        uint256 salt_
    ) public view {
        // Limit fuzz values since we do not allow private keys to be 0 or greater than the group order
        vm.assume(recipientPrivKey_ > 0 && recipientPrivKey_ < ECIES.GROUP_ORDER);
        vm.assume(messagePrivKey_ > 0 && messagePrivKey_ < ECIES.GROUP_ORDER);

        // Calculate public key from recipient private key
        Point memory recipientPubKey = ECIES.calcPubKey(Point(1, 2), recipientPrivKey_);

        // Encrypt the message and track gas usage
        uint256 startGas = gasleft();
        ECIES.encrypt(message_, recipientPubKey, messagePrivKey_, salt_);
        uint256 endGas = gasleft();
        console2.log("Gas used: ", startGas - endGas);
    }
}

contract ECIESEncryptFFITest is ECIESFFITest {
    function test_encrypt() public {
        // Setup encryption parameters
        uint256 message = 1;
        Point memory recipientPubKey = ECIES.calcPubKey(Point(1, 2), 2);
        uint256 privateKey = 3;
        uint256 salt = 1;

        // Encrypt the message using the local library
        (uint256 localCiphertext, Point memory localCiphertextPubKey) =
            ECIES.encrypt(message, recipientPubKey, privateKey, salt);

        // Encrypt the message using the FFI library
        (uint256 ffiCiphertext, Point memory ffiCiphertextPubKey) =
            _encrypt(message, recipientPubKey, privateKey, salt);

        // Confirm the results match
        assertEq(localCiphertext, ffiCiphertext);
        assertEq(localCiphertextPubKey.x, ffiCiphertextPubKey.x);
        assertEq(localCiphertextPubKey.y, ffiCiphertextPubKey.y);
    }

    function testFuzz_encrypt(
        uint256 message_,
        uint256 salt_,
        uint256 recipientPrivKey_,
        uint256 messagePrivKey_
    ) public {
        // Limit fuzz values since we do not allow private keys to be 0 or greater than the group order
        vm.assume(recipientPrivKey_ > 0 && recipientPrivKey_ < ECIES.GROUP_ORDER);
        vm.assume(messagePrivKey_ > 0 && messagePrivKey_ < ECIES.GROUP_ORDER);

        // Calculate public key from recipient private key
        Point memory recipientPubKey = ECIES.calcPubKey(Point(1, 2), recipientPrivKey_);

        // Encrypt the message using the local library
        (uint256 localCiphertext, Point memory localCiphertextPubKey) =
            ECIES.encrypt(message_, recipientPubKey, messagePrivKey_, salt_);

        // Encrypt the message using the FFI library
        (uint256 ffiCiphertext, Point memory ffiCiphertextPubKey) =
            _encrypt(message_, recipientPubKey, messagePrivKey_, salt_);

        // Confirm the results match
        assertEq(localCiphertext, ffiCiphertext);
        assertEq(localCiphertextPubKey.x, ffiCiphertextPubKey.x);
        assertEq(localCiphertextPubKey.y, ffiCiphertextPubKey.y);
    }
}
