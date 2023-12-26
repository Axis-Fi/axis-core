// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Contracts
import {WithModules} from "src/modules/Modules.sol";

contract MockWithModules is WithModules {
    constructor(address _owner) WithModules(_owner) {}
}
