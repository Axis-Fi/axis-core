// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Contracts
import {WithModules, Veecode} from "src/modules/Modules.sol";

contract MockWithModules is WithModules {
    constructor(address _owner) WithModules(_owner) {}

    function execInternalFunction(
        Veecode veecode_,
        bytes calldata callData_
    ) external onlyOwner returns (bytes memory) {
        return execOnModuleInternal(veecode_, callData_);
    }
}
