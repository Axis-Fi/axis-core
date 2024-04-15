/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {FixedPriceSale} from "src/modules/auctions/FPS.sol";
import {BlastGas} from "src/blast/modules/BlastGas.sol";

contract BlastFPSale is FixedPriceSale, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address blast_
    ) FixedPriceSale(auctionHouse_) BlastGas(auctionHouse_, blast_) {}
}
