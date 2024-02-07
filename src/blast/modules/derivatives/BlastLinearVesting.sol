/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";
import {BlastGas} from "src/blast/modules/BlastGas.sol";

contract BlastLSBBA is LinearVesting, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_) LinearVesting(auctionHouse_) BlastGas() {}

    // ========== GAS CLAIM FUNCTIONS ========== //

    function claimGas(address to_) external override onlyParent {
        _claimGas(to_);
    }
}
