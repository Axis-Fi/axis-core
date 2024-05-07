// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {Catalogue} from "src/bases/Catalogue.sol";
import {BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";

/// @notice Contract that provides view functions for batch auctions
contract BatchCatalogue is Catalogue {
    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_) Catalogue(auctionHouse_) {}

    // ========== BATCH AUCTION ========== //

    // ========== RETRIEVING BIDS ========== //

    /// @notice Get the number of bids for a lot
    ///
    /// @param  lotId_  The lot ID
    /// @return         The number of bids
    function getNumBids(uint96 lotId_) public view returns (uint256) {
        BatchAuctionModule module = BatchAuctionHouse(auctionHouse).getBatchModuleForId(lotId_);

        return module.getNumBids(lotId_);
    }

    /// @notice Get a range of bids for a batch auction, based on their current stored order
    /// @dev    This function is used to iterate through bids offline to find indexes for removing a bid
    ///
    /// @param  lotId_  The ID of the lot
    /// @param  start_  The index to start retrieving bid IDs from
    /// @param  count_  The number of bids to retrieve
    function getBidIds(
        uint96 lotId_,
        uint256 start_,
        uint256 count_
    ) public view returns (uint64[] memory) {
        BatchAuctionModule module = BatchAuctionHouse(auctionHouse).getBatchModuleForId(lotId_);

        // Validate on the start index and count is done at the module level
        return module.getBidIds(lotId_, start_, count_);
    }
}
