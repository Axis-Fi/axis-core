// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {BatchScript} from "script/ops/lib/BatchScript.sol";
import {stdJson} from "@forge-std-1.9.1/StdJson.sol";

abstract contract Batch is BatchScript {
    using stdJson for string;

    string internal env;
    string internal chain;
    address safe;

    modifier isBatch(bool send_) {
        // Load environment addresses for chain
        chain = vm.envString("CHAIN");
        env = vm.readFile("./script/env.json");

        // Set safe address
        safe = vm.envAddress("MS"); // MS address

        // Compile batch
        _;

        // Execute batch
        executeBatch(safe, send_);
    }

    function envAddress(string memory key) internal view returns (address) {
        return env.readAddress(string.concat(".", chain, ".", key));
    }
}
