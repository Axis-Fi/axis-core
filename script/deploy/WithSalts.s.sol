/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract WithSalts is Script {
    using stdJson for string;

    string internal constant _saltsPath = "./script/salts.json";
    string internal _saltJson;

    /// @notice Gets the salt for a given key
    /// @dev    If the key is not found, the function will return `bytes32(0)`.
    ///
    /// @param  key_    The key to get the salt for
    /// @return         The salt for the given key
    function _getSalt(string memory key_) internal returns (bytes32) {
        // Load salt file if needed
        if (bytes(_saltJson).length == 0) {
            console2.log("Loaded salts file");
            _saltJson = vm.readFile(_saltsPath);
        }

        bytes32 salt = bytes32(vm.parseJson(_saltJson, string.concat(".", key_)));

        return salt;
    }
}
