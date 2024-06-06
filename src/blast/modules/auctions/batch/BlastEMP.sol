// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {EncryptedMarginalPrice} from "src/modules/auctions/batch/EMP/EMP.sol";
import {BlastGas} from "src/blast/modules/BlastGas.sol";

contract BlastEMP is EncryptedMarginalPrice, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address blast_
    ) EncryptedMarginalPrice(auctionHouse_) BlastGas(auctionHouse_, blast_) {}
}
