// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

// Interfaces
import {IAuctionHouse} from "./interfaces/IAuctionHouse.sol";
import {IBatchCatalogue} from "./interfaces/IBatchCatalogue.sol";
import {IBatchAuction} from "./interfaces/modules/IBatchAuction.sol";

// Base contracts
import {Catalogue} from "./bases/Catalogue.sol";

/// @notice Contract that provides view and aggregation functions for batch auctions without having to know the specific auction module address
contract BatchCatalogue is IBatchCatalogue, Catalogue {
    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_
    ) Catalogue(auctionHouse_) {}

    // ========== RETRIEVING BIDS ========== //

    /// @inheritdoc IBatchCatalogue
    function getNumBids(
        uint96 lotId_
    ) external view returns (uint256) {
        IBatchAuction module =
            IBatchAuction(address(IAuctionHouse(auctionHouse).getAuctionModuleForId(lotId_)));

        return module.getNumBids(lotId_);
    }

    /// @inheritdoc IBatchCatalogue
    function getBidIds(
        uint96 lotId_,
        uint256 start_,
        uint256 count_
    ) external view returns (uint64[] memory) {
        IBatchAuction module =
            IBatchAuction(address(IAuctionHouse(auctionHouse).getAuctionModuleForId(lotId_)));

        // Validate on the start index and count is done at the module level
        return module.getBidIds(lotId_, start_, count_);
    }

    /// @inheritdoc IBatchCatalogue
    function getBidIdAtIndex(uint96 lotId_, uint256 index_) external view returns (uint64) {
        IBatchAuction module =
            IBatchAuction(address(IAuctionHouse(auctionHouse).getAuctionModuleForId(lotId_)));

        return module.getBidIdAtIndex(lotId_, index_);
    }

    /// @inheritdoc IBatchCatalogue
    function getBidClaim(
        uint96 lotId_,
        uint64 bidId_
    ) external view returns (IBatchAuction.BidClaim memory) {
        IBatchAuction module =
            IBatchAuction(address(IAuctionHouse(auctionHouse).getAuctionModuleForId(lotId_)));

        return module.getBidClaim(lotId_, bidId_);
    }
}
