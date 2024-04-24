/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract WithSalts is Test {
    using stdJson for string;

    string internal constant _saltsPath = "./script/salts/salts.json";
    string internal _saltJson;

    /// @notice Gets the salt for a given key
    /// @dev    If the key is not found, the function will return `bytes32(0)`.
    ///
    /// @param  contractName_   The contract to get the salt for
    /// @param  contractCode_   The creation code of the contract
    /// @param  args_           The abi-encoded constructor arguments to the contract
    /// @return                 The salt for the given key
    function _getSalt(
        string memory contractName_,
        bytes memory contractCode_,
        bytes memory args_
    ) internal returns (bytes32) {
        // Load salt file if needed
        if (bytes(_saltJson).length == 0) {
            _saltJson = vm.readFile(_saltsPath);
        }

        // Generate the bytecode hash
        bytes memory bytecode = abi.encodePacked(contractCode_, args_);
        bytes32 bytecodeHash = keccak256(bytecode);

        bytes32 salt = bytes32(
            vm.parseJson(
                _saltJson, string.concat(".", contractName_, ".", vm.toString(bytecodeHash))
            )
        );

        return salt;
    }
}
