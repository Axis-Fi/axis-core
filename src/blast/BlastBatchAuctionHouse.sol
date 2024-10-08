// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {BatchAuctionHouse} from "../BatchAuctionHouse.sol";
import {BlastAuctionHouse} from "./BlastAuctionHouse.sol";

contract BlastBatchAuctionHouse is BatchAuctionHouse, BlastAuctionHouse {
    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address protocol_,
        address permit2_,
        address blast_,
        address weth_,
        address usdb_
    ) BatchAuctionHouse(owner_, protocol_, permit2_) BlastAuctionHouse(blast_, weth_, usdb_) {}
}
