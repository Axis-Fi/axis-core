// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {Keycode, Veecode} from "src/modules/Keycode.sol";

/// @title      ICatalogue
/// @notice     Interface for the Catalogue contract, which provides view functions for auctions
interface ICatalogue {
    // ========== ERRORS ========== //

    error InvalidParams();

    // ========== STATE VARIABLES ========== //

    /// @notice Address of the IAuctionHouse contract
    function auctionHouse() external view returns (address);

    // ========== AUCTION INFORMATION ========== //

    /// @notice     Gets the routing information for a given lot ID
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///
    /// @param      lotId_  ID of the auction lot
    function getRouting(uint96 lotId_) external view returns (IAuctionHouse.Routing memory);

    /// @notice    Gets the fee data for a given lot ID
    /// @dev       The function reverts if:
    ///             - The lot ID is invalid
    ///
    /// @param      lotId_  ID of the auction lot
    function getFeeData(uint96 lotId_) external view returns (IAuctionHouse.FeeData memory);

    /// @notice    Is the auction currently accepting bids or purchases?
    /// @dev       Auctions that have been created, but not yet started will return false
    function isLive(uint96 lotId_) external view returns (bool);

    /// @notice    Is the auction upcoming? (i.e. has not started yet)
    function isUpcoming(uint96 lotId_) external view returns (bool);

    /// @notice    Has the auction ended? (i.e. reached its conclusion and no more bids/purchases can be made)
    function hasEnded(uint96 lotId_) external view returns (bool);

    /// @notice    Capacity remaining for the auction. May be in quote or base tokens, depending on what is allowed for the auction type
    function remainingCapacity(uint96 lotId_) external view returns (uint256);

    // ========== RETRIEVING AUCTIONS ========== //

    /// @notice    ID of the last lot that was created
    function getMaxLotId() external view returns (uint96);

    /// @notice     Returns array of lot IDs for auctions created by a specific seller within the provided range.
    ///
    /// @param      seller_     Address of the seller
    /// @param      startId_    Lot ID to start from
    /// @param      count_      Number of lots to process in this batch
    /// @return     lotIds      Array of lot IDs
    function getAuctionsBySeller(
        address seller_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice     Returns array of lot IDs for auctions that have requested a specific curator within the provided range.
    ///             Lots are returned even if the curator has not approved the curation request.
    ///
    /// @param      curator_    Address of the curator
    /// @param      startId_    Lot ID to start from
    /// @param      count_      Number of lots to process in this batch
    /// @return     lotIds      Array of lot IDs
    function getAuctionsByRequestedCurator(
        address curator_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice     Returns array of lot IDs for auctions that are curated by a specific curator within the provided range.
    ///             Lots are returned only if the curator has approved the curation request.
    ///
    /// @param      curator_    Address of the curator
    /// @param      startId_    Lot ID to start from
    /// @param      count_      Number of lots to process in this batch
    /// @return     lotIds      Array of lot IDs
    function getAuctionsByCurator(
        address curator_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice     Returns array of lot IDs for auctions that have a specific quote token within the provided range.
    ///
    /// @param      quoteToken_ Address of the quote token
    /// @param      startId_    Lot ID to start from
    /// @param      count_      Number of lots to process in this batch
    /// @return     lotIds      Array of lot IDs
    function getAuctionsByQuoteToken(
        address quoteToken_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice     Returns array of lot IDs for auctions that have a specific base token within the provided range.
    ///
    /// @param      baseToken_  Address of the base token
    /// @param      startId_    Lot ID to start from
    /// @param      count_      Number of lots to process in this batch
    /// @return     lotIds      Array of lot IDs
    function getAuctionsByBaseToken(
        address baseToken_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice    Returns array of lot IDs for auctions on a specific auction module within the provided range.
    ///
    /// @param      auctionReference_   Versioned keycode for the auction module
    /// @param      startId_            Lot ID to start from
    /// @param      count_              Number of lots to process in this batch
    /// @return     lotIds              Array of lot IDs
    function getAuctionsByModule(
        Veecode auctionReference_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice    Returns array of lot IDs for auctions that have a specific type within the provided range.
    ///
    /// @param      auctionFormat_  Un-versioned keycode for the auction format
    /// @param      startId_        Lot ID to start from
    /// @param      count_          Number of lots to process in this batch
    /// @return     lotIds          Array of lot IDs
    function getAuctionsByFormat(
        Keycode auctionFormat_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice     Returns array of lot IDs for auctions that have a specific derivative within the provided range.
    ///
    /// @param      derivativeReference_    Versioned keycode for the derivative module
    /// @param      startId_                Lot ID to start from
    /// @param      count_                  Number of lots to process in this batch
    /// @return     lotIds                  Array of lot IDs
    function getAuctionsByDerivative(
        Veecode derivativeReference_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice     Returns array of lot IDs for auctions that are currently live for bidding/purchasing within the provided range.
    ///
    /// @param      startId_    Lot ID to start from
    /// @param      count_      Number of lots to process in this batch
    /// @return     lotIds      Array of lot IDs
    function getLiveAuctions(
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);

    /// @notice     Returns array of lot IDs for auctions that have not started yet within the provided range.
    ///
    /// @param      startId_    Lot ID to start from
    /// @param      count_      Number of lots to process in this batch
    /// @return     lotIds      Array of lot IDs
    function getUpcomingAuctions(
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory lotIds);
}
