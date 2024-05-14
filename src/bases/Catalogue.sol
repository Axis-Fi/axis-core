// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

// Interfaces
import {ICallback} from "src/interfaces/ICallback.sol";
import {IAuction} from "src/interfaces/IAuction.sol";

// External libraries
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

import {Veecode, fromVeecode} from "src/modules/Keycode.sol";

// Auctions
import {AuctionHouse} from "src/bases/AuctionHouse.sol";

/// @notice Contract that provides view functions for auctions
abstract contract Catalogue {
    // ========== ERRORS ========== //
    error InvalidParams();

    // ========== STATE VARIABLES ========== //
    /// @notice Address of the AuctionHouse contract
    address public auctionHouse;

    /// @notice     Fees are in basis points (3 decimals). 1% equals 1000.
    uint48 internal constant _FEE_DECIMALS = 1e5;

    constructor(address auctionHouse_) {
        auctionHouse = auctionHouse_;
    }

    // ========== AUCTION INFORMATION ========== //

    /// @notice     Gets the routing information for a given lot ID
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///
    /// @param      lotId_  ID of the auction lot
    /// @return     routing Routing information for the auction lot
    function getRouting(uint96 lotId_) public view returns (AuctionHouse.Routing memory) {
        (
            address seller,
            ERC20 baseToken,
            ERC20 quoteToken,
            Veecode auctionReference,
            uint256 funding,
            ICallback callbacks,
            Veecode derivativeReference,
            bool wrapDerivative,
            bytes memory derivativeParams
        ) = AuctionHouse(auctionHouse).lotRouting(lotId_);

        return AuctionHouse.Routing({
            auctionReference: auctionReference,
            seller: seller,
            baseToken: baseToken,
            quoteToken: quoteToken,
            callbacks: callbacks,
            derivativeReference: derivativeReference,
            derivativeParams: derivativeParams,
            wrapDerivative: wrapDerivative,
            funding: funding
        });
    }

    /// @notice    Returns whether the auction is currently accepting bids or purchases
    /// @dev       Auctions that have been created, but not yet started will return false
    function isLive(uint96 lotId_) public view returns (bool) {
        IAuction module = AuctionHouse(auctionHouse).getModuleForId(lotId_);

        // Get isLive from module
        return module.isLive(lotId_);
    }

    function hasEnded(uint96 lotId_) external view returns (bool) {
        IAuction module = AuctionHouse(auctionHouse).getModuleForId(lotId_);

        // Get hasEnded from module
        return module.hasEnded(lotId_);
    }

    function remainingCapacity(uint96 lotId_) external view returns (uint256) {
        IAuction module = AuctionHouse(auctionHouse).getModuleForId(lotId_);

        // Get remaining capacity from module
        return module.remainingCapacity(lotId_);
    }

    // ========== RETRIEVING AUCTIONS ========== //

    function getMaxLotId() public view returns (uint96) {
        return AuctionHouse(auctionHouse).lotCounter() - 1;
    }

    function _validateRange(uint96 startId_, uint96 count_) internal view returns (uint256 count) {
        uint96 maxLotId = getMaxLotId();

        // Validate that the startId is not greater than the current lotCounter
        if (startId_ > maxLotId) revert InvalidParams();

        // Set the number of count as the maximum of the count or the remaining lots
        count = startId_ + count_ > maxLotId ? maxLotId - startId_ + 1 : count_;
    }

    function getAuctionsBySeller(
        address seller_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Iterate through the provided range and get the count of auctions owned by the seller in this range
        uint256 sellerCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (getRouting(id).seller == seller_) {
                sellerCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory sellerLots = new uint96[](sellerCount);
        // Add the IDs to the array
        sellerCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (getRouting(id).seller == seller_) {
                sellerLots[sellerCount] = id;
                sellerCount++;
            }
        }

        return sellerLots;
    }

    function getAuctionsByQuoteToken(
        ERC20 quoteToken_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Iterate through the provided range and get the count of auctions with the quoteToken in this range
        uint256 quoteTokenCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (getRouting(id).quoteToken == quoteToken_) {
                quoteTokenCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory quoteTokenLots = new uint96[](quoteTokenCount);
        // Add the IDs to the array
        quoteTokenCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (getRouting(id).quoteToken == quoteToken_) {
                quoteTokenLots[quoteTokenCount] = id;
                quoteTokenCount++;
            }
        }

        return quoteTokenLots;
    }

    function getAuctionsByBaseToken(
        ERC20 baseToken_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Iterate through the provided range and get the count of auctions with the baseToken in this range
        uint256 baseTokenCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (getRouting(id).baseToken == baseToken_) {
                baseTokenCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory baseTokenLots = new uint96[](baseTokenCount);
        // Add the IDs to the array
        baseTokenCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (getRouting(id).baseToken == baseToken_) {
                baseTokenLots[baseTokenCount] = id;
                baseTokenCount++;
            }
        }

        return baseTokenLots;
    }

    function getAuctionsByType(
        Veecode auctionReference_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Iterate through the provided range and get the count of auctions with the auctionReference in this range
        uint256 auctionReferenceCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (fromVeecode(getRouting(id).auctionReference) == fromVeecode(auctionReference_)) {
                auctionReferenceCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory auctionReferenceLots = new uint96[](auctionReferenceCount);
        // Add the IDs to the array
        auctionReferenceCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (fromVeecode(getRouting(id).auctionReference) == fromVeecode(auctionReference_)) {
                auctionReferenceLots[auctionReferenceCount] = id;
                auctionReferenceCount++;
            }
        }

        return auctionReferenceLots;
    }

    function getLiveAuctions(
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Iterate through the provided range and get the count of live auctions in this range
        uint256 liveCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (isLive(id)) {
                liveCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory liveLots = new uint96[](liveCount);
        // Add the IDs to the array
        liveCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            if (isLive(id)) {
                liveLots[liveCount] = id;
                liveCount++;
            }
        }

        return liveLots;
    }
}
