// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Contracts
import {Module, Keycode, toKeycode} from "src/modules/Modules.sol";

contract MockModule is Module {
    constructor(address _owner) Module(_owner) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MOCK");
    }
}
