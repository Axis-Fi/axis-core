// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

// Interfaces
import {ICallback} from "src/interfaces/ICallback.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {ICatalogue} from "src/interfaces/ICatalogue.sol";

// Internal dependencies
import {
    Keycode, keycodeFromVeecode, fromKeycode, Veecode, fromVeecode
} from "src/modules/Keycode.sol";

/// @notice Contract that provides view functions for auctions
abstract contract Catalogue is ICatalogue {
    // ========== STATE VARIABLES ========== //

    /// @inheritdoc ICatalogue
    address public auctionHouse;

    /// @notice     Fees are in basis points (3 decimals). 1% equals 1000.
    uint48 internal constant _FEE_DECIMALS = 1e5;

    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_) {
        auctionHouse = auctionHouse_;
    }

    // ========== AUCTION INFORMATION ========== //

    /// @inheritdoc ICatalogue
    function getRouting(uint96 lotId_) public view returns (IAuctionHouse.Routing memory) {
        (
            address seller,
            address baseToken,
            address quoteToken,
            Veecode auctionReference,
            uint256 funding,
            ICallback callbacks,
            Veecode derivativeReference,
            bool wrapDerivative,
            bytes memory derivativeParams
        ) = IAuctionHouse(auctionHouse).lotRouting(lotId_);

        return IAuctionHouse.Routing({
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

    /// @inheritdoc ICatalogue
    function getFeeData(uint96 lotId_) public view returns (IAuctionHouse.FeeData memory) {
        (
            address curator,
            bool curated,
            uint48 protocolFee,
            uint48 referrerFee,
            uint48 maxCuratorFee
        ) = IAuctionHouse(auctionHouse).lotFees(lotId_);

        return IAuctionHouse.FeeData({
            curator: curator,
            curated: curated,
            curatorFee: maxCuratorFee,
            protocolFee: protocolFee,
            referrerFee: referrerFee
        });
    }

    /// @inheritdoc ICatalogue
    function isLive(uint96 lotId_) public view returns (bool) {
        IAuction module = IAuctionHouse(auctionHouse).getAuctionModuleForId(lotId_);

        // Get isLive from module
        return module.isLive(lotId_);
    }

    /// @inheritdoc ICatalogue
    function isUpcoming(uint96 lotId_) public view returns (bool) {
        IAuction module = IAuctionHouse(auctionHouse).getAuctionModuleForId(lotId_);

        // Get isUpcoming from module
        return module.isUpcoming(lotId_);
    }

    /// @inheritdoc ICatalogue
    function hasEnded(uint96 lotId_) external view returns (bool) {
        IAuction module = IAuctionHouse(auctionHouse).getAuctionModuleForId(lotId_);

        // Get hasEnded from module
        return module.hasEnded(lotId_);
    }

    /// @inheritdoc ICatalogue
    function remainingCapacity(uint96 lotId_) external view returns (uint256) {
        IAuction module = IAuctionHouse(auctionHouse).getAuctionModuleForId(lotId_);

        // Get remaining capacity from module
        return module.remainingCapacity(lotId_);
    }

    // ========== RETRIEVING AUCTIONS ========== //

    /// @inheritdoc ICatalogue
    function getMaxLotId() public view returns (uint96) {
        return IAuctionHouse(auctionHouse).lotCounter() - 1;
    }

    function _validateRange(uint96 startId_, uint96 count_) internal view returns (uint256 count) {
        uint96 maxLotId = getMaxLotId();

        // Validate that the startId is not greater than the current lotCounter
        if (startId_ > maxLotId) revert InvalidParams();

        // Set the number of count as the maximum of the count or the remaining lots
        count = startId_ + count_ > maxLotId ? maxLotId - startId_ + 1 : count_;
    }

    /// @inheritdoc ICatalogue
    function getAuctionsBySeller(
        address seller_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        address[] memory sellers = new address[](count);

        // Iterate through the provided range and get the count of auctions owned by the seller in this range
        uint256 sellerCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            sellers[ix] = getRouting(id).seller;
            if (sellers[ix] == seller_) {
                sellerCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory sellerLots = new uint96[](sellerCount);
        // Add the IDs to the array
        sellerCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (sellers[ix] == seller_) {
                sellerLots[sellerCount] = id;
                sellerCount++;
            }
        }

        return sellerLots;
    }

    /// @inheritdoc ICatalogue
    function getAuctionsByRequestedCurator(
        address curator_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        address[] memory curators = new address[](count);

        // Iterate through the provided range and get the count of auctions curated by the curator in this range
        uint256 curatorCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            curators[ix] = getFeeData(id).curator;
            if (curators[ix] == curator_) {
                curatorCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory curatorLots = new uint96[](curatorCount);
        // Add the IDs to the array
        curatorCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (curators[ix] == curator_) {
                curatorLots[curatorCount] = id;
                curatorCount++;
            }
        }

        return curatorLots;
    }

    /// @inheritdoc ICatalogue
    function getAuctionsByCurator(
        address curator_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        IAuctionHouse.FeeData[] memory feeData = new IAuctionHouse.FeeData[](count);

        // Iterate through the provided range and get the count of auctions curated by the curator in this range
        uint256 curatorCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            feeData[ix] = getFeeData(id);
            if (feeData[ix].curator == curator_ && feeData[ix].curated) {
                curatorCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory curatorLots = new uint96[](curatorCount);
        // Add the IDs to the array
        curatorCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (feeData[ix].curator == curator_ && feeData[ix].curated) {
                curatorLots[curatorCount] = id;
                curatorCount++;
            }
        }

        return curatorLots;
    }

    /// @inheritdoc ICatalogue
    function getAuctionsByQuoteToken(
        address quoteToken_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        address[] memory quoteTokens = new address[](count);

        // Iterate through the provided range and get the count of auctions with the quoteToken in this range
        uint256 quoteTokenCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            quoteTokens[ix] = address(getRouting(id).quoteToken);
            if (quoteTokens[ix] == quoteToken_) {
                quoteTokenCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory quoteTokenLots = new uint96[](quoteTokenCount);
        // Add the IDs to the array
        quoteTokenCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (quoteTokens[ix] == quoteToken_) {
                quoteTokenLots[quoteTokenCount] = id;
                quoteTokenCount++;
            }
        }

        return quoteTokenLots;
    }

    /// @inheritdoc ICatalogue
    function getAuctionsByBaseToken(
        address baseToken_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        address[] memory baseTokens = new address[](count);

        // Iterate through the provided range and get the count of auctions with the baseToken in this range
        uint256 baseTokenCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            baseTokens[ix] = address(getRouting(id).baseToken);
            if (baseTokens[ix] == baseToken_) {
                baseTokenCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory baseTokenLots = new uint96[](baseTokenCount);
        // Add the IDs to the array
        baseTokenCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (baseTokens[ix] == baseToken_) {
                baseTokenLots[baseTokenCount] = id;
                baseTokenCount++;
            }
        }

        return baseTokenLots;
    }

    /// @inheritdoc ICatalogue
    function getAuctionsByModule(
        Veecode auctionReference_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        bytes7 auctionRef = fromVeecode(auctionReference_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        bytes7[] memory auctionRefs = new bytes7[](count);

        // Iterate through the provided range and get the count of auctions with the auctionReference in this range
        uint256 auctionReferenceCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            auctionRefs[ix] = fromVeecode(getRouting(id).auctionReference);
            if (auctionRefs[ix] == auctionRef) {
                auctionReferenceCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory auctionReferenceLots = new uint96[](auctionReferenceCount);
        // Add the IDs to the array
        auctionReferenceCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (auctionRefs[ix] == auctionRef) {
                auctionReferenceLots[auctionReferenceCount] = id;
                auctionReferenceCount++;
            }
        }

        return auctionReferenceLots;
    }

    /// @inheritdoc ICatalogue
    function getAuctionsByFormat(
        Keycode auctionFormat_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        bytes5 auctionFormat = fromKeycode(auctionFormat_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        bytes5[] memory auctionFormats = new bytes5[](count);

        // Iterate through the provided range and get the count of auctions with the auctionFormat in this range
        uint256 auctionFormatCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            auctionFormats[ix] = fromKeycode(keycodeFromVeecode(getRouting(id).auctionReference));
            if (auctionFormats[ix] == auctionFormat) {
                auctionFormatCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory auctionFormatLots = new uint96[](auctionFormatCount);

        // Add the IDs to the array
        auctionFormatCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (auctionFormats[ix] == auctionFormat) {
                auctionFormatLots[auctionFormatCount] = id;
                auctionFormatCount++;
            }
        }

        return auctionFormatLots;
    }

    /// @inheritdoc ICatalogue
    function getAuctionsByDerivative(
        Veecode derivativeReference_,
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        bytes7 derivativeRef = fromVeecode(derivativeReference_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        bytes7[] memory derivativeRefs = new bytes7[](count);

        // Iterate through the provided range and get the count of auctions with the derivativeReference in this range
        uint256 derivativeReferenceCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            derivativeRefs[ix] = fromVeecode(getRouting(id).derivativeReference);
            if (derivativeRefs[ix] == derivativeRef) {
                derivativeReferenceCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory derivativeReferenceLots = new uint96[](derivativeReferenceCount);

        // Add the IDs to the array
        derivativeReferenceCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (derivativeRefs[ix] == derivativeRef) {
                derivativeReferenceLots[derivativeReferenceCount] = id;
                derivativeReferenceCount++;
            }
        }

        return derivativeReferenceLots;
    }

    /// @inheritdoc ICatalogue
    function getLiveAuctions(
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        bool[] memory live = new bool[](count);

        // Iterate through the provided range and get the count of live auctions in this range
        uint256 liveCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            live[ix] = isLive(id);
            if (live[ix]) {
                liveCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory liveLots = new uint96[](liveCount);
        // Add the IDs to the array
        liveCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (live[ix]) {
                liveLots[liveCount] = id;
                liveCount++;
            }
        }

        return liveLots;
    }

    /// @inheritdoc ICatalogue
    function getUpcomingAuctions(
        uint96 startId_,
        uint96 count_
    ) external view returns (uint96[] memory) {
        uint256 count = _validateRange(startId_, count_);

        // Cache the data from the external call on the first iteration to avoid duplicates calls
        bool[] memory upcoming = new bool[](count);

        // Iterate through the provided range and get the count of upcoming auctions in this range
        uint256 upcomingCount;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            upcoming[ix] = isUpcoming(id);
            if (upcoming[ix]) {
                upcomingCount++;
            }
        }

        // Create an array to store the auction IDs
        uint96[] memory upcomingLots = new uint96[](upcomingCount);
        // Add the IDs to the array
        upcomingCount = 0;
        for (uint96 id = startId_; id < startId_ + count; id++) {
            uint96 ix = id - startId_;
            if (upcoming[ix]) {
                upcomingLots[upcomingCount] = id;
                upcomingCount++;
            }
        }

        return upcomingLots;
    }
}
