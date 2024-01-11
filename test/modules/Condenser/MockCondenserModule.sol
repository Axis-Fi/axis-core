// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Condenser
import {CondenserModule} from "src/modules/Condenser.sol";

contract MockCondenserModule is CondenserModule {
    constructor(address _owner) Module(_owner) {}

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("COND"), 1);
    }

    function TYPE() public pure virtual override returns (Type) {
        return Type.Condenser;
    }

    function condense(
        bytes memory auctionOutput_,
        bytes memory derivativeConfig_
    ) external pure virtual override returns (bytes memory) {}
}
