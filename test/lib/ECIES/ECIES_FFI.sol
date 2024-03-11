// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Testing Libraries
import {Test} from "forge-std/Test.sol";

// ECIES
import {Point} from "src/lib/ECIES.sol";

abstract contract ECIESFFITest is Test {
    string internal constant _EXECUTABLE = "./crates/ecies-cli/target/debug/ecies-cli";

    function _encrypt(
        uint256 message_,
        Point memory publicKey_,
        uint256 privateKey_,
        uint256 salt_
    ) internal returns (uint256 ciphertext_, Point memory bidPublicKey_) {
        // Construct the input strings
        string memory message = vm.toString(message_);
        string memory publicKeyX = vm.toString(publicKey_.x);
        string memory publicKeyY = vm.toString(publicKey_.y);
        string memory privateKey = vm.toString(privateKey_);
        string memory salt = vm.toString(salt_);

        // Create inputs for the FFI
        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(
            _EXECUTABLE,
            " encrypt ",
            message,
            " ",
            publicKeyX,
            " ",
            publicKeyY,
            " ",
            privateKey,
            " ",
            salt
        );

        // Execute the FFI
        bytes memory output = vm.ffi(inputs);

        // Decode the output and assign to return variables
        (ciphertext_, bidPublicKey_) = abi.decode(output, (uint256, Point));
    }

    function _decrypt(
        uint256 cipherText_,
        Point memory bidPublicKey_,
        uint256 privateKey_,
        uint256 salt_
    ) internal returns (uint256 message_) {
        // Construct the input strings
        string memory cipherText = vm.toString(cipherText_);
        string memory bidPublicKeyX = vm.toString(bidPublicKey_.x);
        string memory bidPublicKeyY = vm.toString(bidPublicKey_.y);
        string memory privateKey = vm.toString(privateKey_);
        string memory salt = vm.toString(salt_);

        // Create inputs for the FFI
        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(
            _EXECUTABLE,
            " decrypt ",
            cipherText,
            " ",
            bidPublicKeyX,
            " ",
            bidPublicKeyY,
            " ",
            privateKey,
            " ",
            salt
        );

        // Execute the FFI
        bytes memory result = vm.ffi(inputs);

        // Decode output and assign to return variable
        message_ = abi.decode(result, (uint256));
    }
}
