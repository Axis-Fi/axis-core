/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract WithSalts is Test {
    using stdJson for string;

    string internal constant _saltsPath = "./script/salts.json";
    string internal _saltJson;

    function _getSalt(string memory key_) internal returns (bytes32) {
        // Load salt file if needed
        if (bytes(_saltJson).length == 0) {
            console2.log("Loaded salts file");
            _saltJson = vm.readFile(_saltsPath);
        }

        bytes32 salt = bytes32(vm.parseJson(_saltJson, string.concat(".", key_)));

        // Revert if the salt is not set
        require(salt != bytes32(0), string.concat("Salt not found for key:", key_));

        return salt;
    }
}
