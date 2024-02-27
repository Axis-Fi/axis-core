/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";
import {BlastGas} from "src/blast/modules/BlastGas.sol";

contract BlastEMPAM is EncryptedMarginalPriceAuctionModule, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_)
        EncryptedMarginalPriceAuctionModule(auctionHouse_)
        BlastGas(auctionHouse_)
    {}
}
