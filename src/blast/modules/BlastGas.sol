/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

interface IBlast {
    function configureClaimableGas() external;
    function claimMaxGas(address contractAddress, address recipient) external returns (uint256);
}

abstract contract BlastGas {
    // ========== STATE VARIABLES ========== //

    /// @notice    Address of the Blast contract
    IBlast internal constant _BLAST = IBlast(0x4300000000000000000000000000000000000002);

    // ========== CONSTRUCTOR ========== //

    constructor() {
        // Set gas fees to claimable for the module
        _BLAST.configureClaimableGas();
    }

    // ========== GAS CLAIM FUNCTIONS ========== //

    function _claimGas(address to_) internal {
        _BLAST.claimMaxGas(address(this), to_);
    }

    function claimGas(address to_) external virtual;
}
