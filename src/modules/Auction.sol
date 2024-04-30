// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/IAuction.sol";
import {Module} from "src/modules/Modules.sol";

abstract contract AuctionModule is IAuction, Module {
    // ========= STATE ========== //

    /// @notice Minimum auction duration in seconds
    uint48 public minAuctionDuration;

    /// @notice Constant for percentages
    /// @dev    1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint48 internal constant _ONE_HUNDRED_PERCENT = 100_000;

    /// @notice General information pertaining to auction lots
    mapping(uint96 id => Lot lot) public lotData;

    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_) Module(auctionHouse_) {}

    /// @inheritdoc Module
    function TYPE() public pure override returns (Type) {
        return Type.Auction;
    }

    // ========== AUCTION MANAGEMENT ========== //

    /// @inheritdoc IAuction
    /// @dev        If the start time is zero, the auction will have a start time of the current block timestamp.
    ///
    ///             This function handles the following:
    ///             - Validates the lot parameters
    ///             - Stores the auction lot
    ///             - Calls the implementation-specific function
    ///
    ///             This function reverts if:
    ///             - The caller is not the parent of the module
    ///             - The start time is in the past
    ///             - The duration is less than the minimum
    function auction(
        uint96 lotId_,
        AuctionParams memory params_,
        uint8 quoteTokenDecimals_,
        uint8 baseTokenDecimals_
    ) external virtual override onlyInternal {
        // Start time must be zero or in the future
        if (params_.start > 0 && params_.start < uint48(block.timestamp)) {
            revert Auction_InvalidStart(params_.start, uint48(block.timestamp));
        }

        // Duration must be at least min duration
        if (params_.duration < minAuctionDuration) {
            revert Auction_InvalidDuration(params_.duration, minAuctionDuration);
        }

        // Create core market data
        Lot memory lot;
        lot.start = params_.start == 0 ? uint48(block.timestamp) : params_.start;
        lot.conclusion = lot.start + params_.duration;
        lot.quoteTokenDecimals = quoteTokenDecimals_;
        lot.baseTokenDecimals = baseTokenDecimals_;
        lot.capacityInQuote = params_.capacityInQuote;
        lot.capacity = params_.capacity;

        // Call internal createAuction function to store implementation-specific data
        _auction(lotId_, lot, params_.implParams);

        // Store lot data
        lotData[lotId_] = lot;
    }

    /// @notice     Implementation-specific auction creation logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_              The lot ID
    /// @param      lot_                The lot data
    /// @param      params_             Additional auction parameters
    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal virtual;

    /// @notice     Cancel an auction lot
    /// @dev        Assumptions:
    ///             - The parent will refund the seller the remaining capacity
    ///             - The parent will verify that the caller is the seller
    ///
    ///             This function handles the following:
    ///             - Calls the implementation-specific function
    ///             - Updates the lot data
    ///
    ///             This function reverts if:
    ///             - the caller is not the parent of the module
    ///             - the lot id is invalid
    ///             - the lot has concluded
    ///
    /// @param      lotId_      The lot id
    function cancelAuction(uint96 lotId_) external virtual override onlyInternal {
        // Validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotConcluded(lotId_);

        // Call internal closeAuction function to update any other required parameters
        _cancelAuction(lotId_);

        // Update lot
        Lot storage lot = lotData[lotId_];

        lot.conclusion = uint48(block.timestamp);
        lot.capacity = 0;
    }

    /// @notice     Implementation-specific auction cancellation logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_      The lot ID
    function _cancelAuction(uint96 lotId_) internal virtual;

    // ========== AUCTION INFORMATION ========== //

    /// @inheritdoc IAuction
    /// @dev        A lot is active if:
    ///             - The lot has not concluded
    ///             - The lot has started
    ///             - The lot has not sold out or been cancelled (capacity > 0)
    ///
    /// @param      lotId_  The lot ID
    /// @return     bool    Whether or not the lot is active
    function isLive(uint96 lotId_) public view override returns (bool) {
        return (
            lotData[lotId_].capacity != 0 && uint48(block.timestamp) < lotData[lotId_].conclusion
                && uint48(block.timestamp) >= lotData[lotId_].start
        );
    }

    /// @inheritdoc IAuction
    function hasEnded(uint96 lotId_) public view override returns (bool) {
        return
            uint48(block.timestamp) >= lotData[lotId_].conclusion || lotData[lotId_].capacity == 0;
    }

    /// @inheritdoc IAuction
    function remainingCapacity(uint96 lotId_) external view override returns (uint256) {
        return lotData[lotId_].capacity;
    }

    /// @inheritdoc IAuction
    function capacityInQuote(uint96 lotId_) external view override returns (bool) {
        return lotData[lotId_].capacityInQuote;
    }

    /// @inheritdoc IAuction
    function getLot(uint96 lotId_) external view override returns (Lot memory) {
        return lotData[lotId_];
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice     Set the minimum auction duration
    /// @dev        This function must be called by the parent AuctionHouse, and
    ///             can be called by governance using `execOnModule`.
    function setMinAuctionDuration(uint48 duration_) external onlyParent {
        minAuctionDuration = duration_;
    }

    // ========== MODIFIERS ========== //

    /// @notice     Checks that `lotId_` is valid
    /// @dev        Should revert if the lot ID is invalid
    ///             Inheriting contracts can override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotInvalid(uint96 lotId_) internal view virtual {
        if (lotData[lotId_].start == 0) revert Auction_InvalidLotId(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` has not started
    /// @dev        Should revert if the lot has not started
    function _revertIfBeforeLotStart(uint96 lotId_) internal view virtual {
        if (uint48(block.timestamp) < lotData[lotId_].start) revert Auction_LotNotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` has started
    /// @dev        Should revert if the lot has started
    function _revertIfLotStarted(uint96 lotId_) internal view virtual {
        if (uint48(block.timestamp) >= lotData[lotId_].start) revert Auction_LotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` has not concluded
    /// @dev        Should revert if the lot has not concluded
    function _revertIfBeforeLotConcluded(uint96 lotId_) internal view virtual {
        if (uint48(block.timestamp) < lotData[lotId_].conclusion && lotData[lotId_].capacity > 0) {
            revert Auction_LotNotConcluded(lotId_);
        }
    }

    /// @notice     Checks that the lot represented by `lotId_` has not concluded
    /// @dev        Should revert if the lot has concluded
    function _revertIfLotConcluded(uint96 lotId_) internal view virtual {
        // Beyond the conclusion time
        if (uint48(block.timestamp) >= lotData[lotId_].conclusion) {
            revert Auction_LotNotActive(lotId_);
        }

        // Capacity is sold-out, or cancelled
        if (lotData[lotId_].capacity == 0) revert Auction_LotNotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` is active
    /// @dev        Should revert if the lot is not active
    ///             Inheriting contracts can override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotInactive(uint96 lotId_) internal view virtual {
        if (!isLive(lotId_)) revert Auction_LotNotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` is active
    /// @dev        Should revert if the lot is active
    ///             Inheriting contracts can override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotActive(uint96 lotId_) internal view virtual {
        if (isLive(lotId_)) revert Auction_LotActive(lotId_);
    }
}
