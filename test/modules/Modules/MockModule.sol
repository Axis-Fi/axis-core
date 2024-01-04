// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Contracts
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

contract MockModuleV1 is Module {
    constructor(address _owner) Module(_owner) {}

    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("MOCK"), 1);
    }

    function mock() external pure returns (bool) {
        return true;
    }
}

contract MockModuleV2 is Module {
    constructor(address _owner) Module(_owner) {}

    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("MOCK"), 2);
    }
}

contract MockModuleV3 is Module {
    constructor(address _owner) Module(_owner) {}

    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("MOCK"), 3);
    }
}

contract MockModuleV0 is Module {
    constructor(address _owner) Module(_owner) {}

    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("MOCK"), 0);
    }
}

contract MockInvalidModule is Module {
    constructor(address _owner) Module(_owner) {}

    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("INVA_"), 100);
    }
}
