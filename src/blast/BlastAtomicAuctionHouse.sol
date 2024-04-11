/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {BlastAuctionHouse} from "src/blast/BlastAuctionHouse.sol";

contract BlastAtomicAuctionHouse is AtomicAuctionHouse, BlastAuctionHouse {

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address protocol_,
        address permit2_,
        address blast_,
        address weth_,
        address usdb_
    ) AtomicAuctionHouse(owner_, protocol_, permit2_) BlastAuctionHouse(blast_, weth_, usdb_) {}

}
