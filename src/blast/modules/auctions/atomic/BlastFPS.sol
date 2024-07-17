// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {FixedPriceSale} from "../../../../modules/auctions/atomic/FPS.sol";
import {BlastGas} from "../../BlastGas.sol";

contract BlastFPS is FixedPriceSale, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address blast_
    ) FixedPriceSale(auctionHouse_) BlastGas(auctionHouse_, blast_) {}
}
