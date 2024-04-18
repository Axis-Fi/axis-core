// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

abstract contract WithEnvironment is Script {
    using stdJson for string;

    string public chain;
    string public env;

    function _loadEnv(string calldata chain_) internal {
        chain = chain_;
        console2.log("Using chain:", chain_);

        // Load environment file
        env = vm.readFile("./script/env.json");
    }

    function _envAddress(string memory key_) internal view returns (address) {
        return env.readAddress(string.concat(".current.", chain, ".", key_));
    }
}