// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";

abstract contract Condenser {
    function condense(
        bytes memory auctionOutput_,
        bytes memory derivativeConfig_
    ) external pure virtual returns (bytes memory);
}

abstract contract CondenserModule is Condenser, Module {}
