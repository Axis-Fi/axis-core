/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {LocalSealedBidBatchAuction} from "src/modules/auctions/LSBBA/LSBBA.sol";
import {BlastGas} from "src/blast/modules/BlastGas.sol";

contract BlastLSBBA is LocalSealedBidBatchAuction, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_)
        LocalSealedBidBatchAuction(auctionHouse_)
        BlastGas(auctionHouse_)
    {}
}
