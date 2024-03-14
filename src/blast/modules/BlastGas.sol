/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IBlast {
    function configureGovernor(address governor_) external;
}

abstract contract BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(address parent_) {
        // Configure governor to claim gas fees
        IBlast(0x4300000000000000000000000000000000000002).configureGovernor(parent_);
    }
}
