// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {stdJson} from "@forge-std-1.9.1/StdJson.sol";

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
        // TODO consider returning address(0) if not found
        return env.readAddress(string.concat(".current.", chain, ".", key_));
    }

    function _envAddressNotZero(string memory key_) internal view returns (address) {
        address addr = _envAddress(key_);
        require(
            addr != address(0), string.concat("WithEnvironment: key '", key_, "' has zero address")
        );

        console2.log("    %s: %s (from env.json)", key_, addr);
        return addr;
    }
}
