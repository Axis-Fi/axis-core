// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

interface IBlast {
    function configureClaimableGas() external;

    function configureGovernor(address governor_) external;
}

abstract contract BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(address parent_, address blast_) {
        // Configure gas as claimable
        IBlast(blast_).configureClaimableGas();
        // Configure governor to claim gas fees
        IBlast(blast_).configureGovernor(parent_);
    }
}
