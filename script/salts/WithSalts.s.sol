/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Script} from "@forge-std-1.9.1/Script.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";
import {stdJson} from "@forge-std-1.9.1/StdJson.sol";

contract WithSalts is Script {
    using stdJson for string;

    string internal constant _SALTS_PATH = "./script/salts/salts.json";
    string internal constant _BYTECODE_DIR = "bytecode";
    string internal _saltJson;

    function _getBytecodeDirectory() internal pure returns (string memory) {
        return string.concat("./", _BYTECODE_DIR);
    }

    function _getBytecodePath(string memory name_) internal pure returns (string memory) {
        return string.concat(_getBytecodeDirectory(), "/", name_, ".bin");
    }

    function _createBytecodeDirectory() internal {
        // Create the bytecode folder if it doesn't exist
        if (!vm.isDir(_getBytecodeDirectory())) {
            console2.log("Creating bytecode directory");

            string[] memory inputs = new string[](2);
            inputs[0] = "mkdir";
            inputs[1] = _BYTECODE_DIR;

            vm.ffi(inputs);
        }
    }

    function _writeBytecode(
        string memory contractName_,
        bytes memory creationCode_,
        bytes memory contractArgs_
    ) internal returns (string memory bytecodePath, bytes32 bytecodeHash) {
        // Calculate salt for the contract
        bytes memory bytecode = abi.encodePacked(creationCode_, contractArgs_);
        bytecodeHash = keccak256(bytecode);

        bytecodePath = _getBytecodePath(contractName_);
        vm.writeFile(bytecodePath, vm.toString(bytecode));

        return (bytecodePath, bytecodeHash);
    }

    /// @notice Gets the salt for a given key
    /// @dev    If the key is not found, the function will return `bytes32(0)`.
    ///
    /// @param  contractName_   The contract to get the salt for
    /// @param  creationCode_   The creation code of the contract
    /// @param  contractArgs_   The abi-encoded constructor arguments to the contract
    /// @return                 The salt for the given key
    function _getSalt(
        string memory contractName_,
        bytes memory creationCode_,
        bytes memory contractArgs_
    ) internal returns (bytes32) {
        // Load salt file if needed
        if (bytes(_saltJson).length == 0) {
            _saltJson = vm.readFile(_SALTS_PATH);
        }

        bytes32 salt = bytes32(
            vm.parseJson(
                _saltJson,
                string.concat(
                    ".",
                    contractName_,
                    ".",
                    vm.toString(keccak256(abi.encodePacked(creationCode_, contractArgs_)))
                )
            )
        );

        return salt;
    }

    /// @notice Same as `_setSalt()`, but prefixes the salt key with "Test_" so they are co-located and separate from production salts.
    function _setTestSalt(
        string memory bytecodePath_,
        string memory prefix_,
        string memory saltKey_,
        bytes32 bytecodeHash_
    ) internal {
        _setSalt(bytecodePath_, prefix_, string.concat("Test_", saltKey_), bytecodeHash_);
    }

    /// @notice Same as `_setSalt()`, but prefixes the salt key with "Test_" so they are co-located and separate from production salts.
    function _setTestSaltWithDeployer(
        string memory bytecodePath_,
        string memory prefix_,
        string memory saltKey_,
        bytes32 bytecodeHash_,
        address deployer_
    ) internal {
        _setSaltWithDeployer(
            bytecodePath_, prefix_, string.concat("Test_", saltKey_), bytecodeHash_, deployer_
        );
    }

    /// @notice Calls a script to generate and write the salt for a given bytecode
    ///
    /// @param  bytecodePath_   The path to the bytecode
    /// @param  prefix_         The prefix to use for the salt, e.g. "98"
    /// @param  saltKey_        The key to write the salt to
    /// @param  bytecodeHash_   The keccak256 hash of the bytecode, used to uniquely identify the contract version and arguments
    function _setSalt(
        string memory bytecodePath_,
        string memory prefix_,
        string memory saltKey_,
        bytes32 bytecodeHash_
    ) internal {
        // Call the salts script to generate and write the salt
        string[] memory inputs = new string[](9);
        inputs[0] = "./script/salts/write_salt.sh";
        inputs[1] = "--bytecodeFile";
        inputs[2] = bytecodePath_;
        inputs[3] = "--prefix";
        inputs[4] = prefix_;
        inputs[5] = "--saltKey";
        inputs[6] = saltKey_;
        inputs[7] = "--bytecodeHash";
        inputs[8] = vm.toString(bytecodeHash_);

        vm.ffi(inputs);

        console2.log("Salt set for", saltKey_, "with prefix", prefix_);
    }

    function _setSaltWithDeployer(
        string memory bytecodePath_,
        string memory prefix_,
        string memory saltKey_,
        bytes32 bytecodeHash_,
        address deployer_
    ) internal {
        // Call the salts script to generate and write the salt
        string[] memory inputs = new string[](11);
        inputs[0] = "./script/salts/write_salt.sh";
        inputs[1] = "--bytecodeFile";
        inputs[2] = bytecodePath_;
        inputs[3] = "--prefix";
        inputs[4] = prefix_;
        inputs[5] = "--saltKey";
        inputs[6] = saltKey_;
        inputs[7] = "--bytecodeHash";
        inputs[8] = vm.toString(bytecodeHash_);
        inputs[9] = "--deployer";
        inputs[10] = vm.toString(deployer_);

        vm.ffi(inputs);

        console2.log("Salt set for", saltKey_, "with prefix", prefix_);
    }
}
