/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";
import {BlastGas} from "src/blast/modules/BlastGas.sol";

contract BlastLinearVesting is LinearVesting, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_) LinearVesting(auctionHouse_) BlastGas(auctionHouse_) {}
}
