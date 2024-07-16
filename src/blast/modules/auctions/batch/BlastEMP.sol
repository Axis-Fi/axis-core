// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {EncryptedMarginalPrice} from "../../../../modules/auctions/batch/EMP.sol";
import {BlastGas} from "../../BlastGas.sol";

contract BlastEMP is EncryptedMarginalPrice, BlastGas {
    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address blast_
    ) EncryptedMarginalPrice(auctionHouse_) BlastGas(auctionHouse_, blast_) {}
}
