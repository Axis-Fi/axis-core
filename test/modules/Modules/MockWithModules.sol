// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Contracts
import {WithModules, Veecode} from "src/modules/Modules.sol";

import {MockModuleV1} from "test/modules/Modules/MockModule.sol";

contract MockWithModules is WithModules {
    constructor(address _owner) WithModules(_owner) {}

    function callProhibited(Veecode veecode_) external view returns (bool) {
        MockModuleV1 module = MockModuleV1(_getModuleIfInstalled(veecode_));

        return module.prohibited();
    }
}
