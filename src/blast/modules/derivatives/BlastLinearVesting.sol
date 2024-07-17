// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {LinearVesting} from "../../../modules/derivatives/LinearVesting.sol";
import {BlastGas} from "../BlastGas.sol";

contract BlastLinearVesting is LinearVesting, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address blast_
    ) LinearVesting(auctionHouse_) BlastGas(auctionHouse_, blast_) {}
}
