/// SPDX-License-Identifier: APGL-3.0
pragma solidity 0.8.19;

import {Catalogue} from "src/bases/Catalogue.sol";
import {BatchAuction} from "src/modules/auctions/BatchAuctionModule.sol";
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {FeeManager} from "src/bases/FeeManager.sol";
import {keycodeFromVeecode, Keycode} from "src/modules/Modules.sol";

/// @notice Contract that provides view functions for Batch Auctions
contract BatchCatalogue is Catalogue {

    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_) Catalogue(auctionHouse_) {}

    // ========== BATCH AUCTION ========== //

    // ========== RETRIEVING AUCTION IDS ========== //

    // TODO determine if we even need a batch catalogue. EMP has most status' locally, instead of at the batch level.
}