// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Contracts
import {Module, Keycode, toKeycode, toModuleKeycode} from "src/modules/Modules.sol";

contract MockModule is Module {
    constructor(address _owner) Module(_owner) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode(toModuleKeycode("MOCK"), 1);
    }
}

contract MockInvalidModule is Module {
    constructor(address _owner) Module(_owner) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode(toModuleKeycode("INVA_"), 100);
    }
}

contract MockUpgradedModule is Module {
    constructor(address _owner) Module(_owner) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode(toModuleKeycode("MOCK"), 2);
    }
}
