/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {FixedPriceAuctionModule} from "src/modules/auctions/FPAM.sol";
import {BlastGas} from "src/blast/modules/BlastGas.sol";

contract BlastFPAM is FixedPriceAuctionModule, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_)
        FixedPriceAuctionModule(auctionHouse_)
        BlastGas(auctionHouse_)
    {}
}
