/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";

abstract contract Auction {
    /* ========== ERRORS ========== */

    error Auction_MarketNotActive(uint96 lotId);

    error Auction_MarketActive(uint96 lotId);

    error Auction_InvalidStart(uint48 start_, uint48 minimum_);

    error Auction_InvalidDuration(uint48 duration_, uint48 minimum_);

    error Auction_InvalidLotId(uint96 lotId);

    error Auction_InvalidBidId(uint96 lotId, uint96 bidId);

    error Auction_OnlyMarketOwner();
    error Auction_AmountLessThanMinimum();
    error Auction_NotEnoughCapacity();
    error Auction_InvalidParams();
    error Auction_NotAuthorized();
    error Auction_NotImplemented();

    error Auction_NotBidder();

    /* ========== EVENTS ========== */

    event AuctionCreated(
        uint256 indexed id, address indexed payoutToken, address indexed quoteToken
    );
    event AuctionClosed(uint256 indexed id);

    // ========== DATA STRUCTURES ========== //

    /// @notice     Core data for an auction lot
    ///
    /// @param      start               The timestamp when the auction starts
    /// @param      conclusion          The timestamp when the auction ends
    /// @param      quoteTokenDecimals  The quote token decimals
    /// @param      baseTokenDecimals   The base token decimals
    /// @param      capacityInQuote     Whether or not the capacity is in quote tokens
    /// @param      capacity            The capacity of the lot
    /// @param      sold                The amount of base tokens sold
    /// @param      purchased           The amount of quote tokens purchased
    struct Lot {
        uint48 start;
        uint48 conclusion;
        uint8 quoteTokenDecimals;
        uint8 baseTokenDecimals;
        bool capacityInQuote;
        uint256 capacity;
        uint256 sold;
        uint256 purchased;
    }

    /// @notice     Core data for a bid
    ///
    /// @param      bidder          The address of the bidder
    /// @param      recipient       The address of the recipient
    /// @param      referrer        The address of the referrer
    /// @param      amount          The amount of quote tokens bid
    /// @param      minAmountOut    The minimum amount of base tokens to receive
    /// @param      auctionParam    The auction-specific parameter for the bid
    struct Bid {
        address bidder;
        address recipient;
        address referrer;
        uint256 amount;
        uint256 minAmountOut;
        bytes auctionParam;
    }

    /// @notice     Parameters when creating an auction lot
    ///
    /// @param      start           The timestamp when the auction starts
    /// @param      duration        The duration of the auction (in seconds)
    /// @param      capacityInQuote Whether or not the capacity is in quote tokens
    /// @param      capacity        The capacity of the lot
    /// @param      implParams      Abi-encoded implementation-specific parameters
    struct AuctionParams {
        uint48 start;
        uint48 duration;
        bool capacityInQuote;
        uint256 capacity;
        bytes implParams;
    }

    // ========= STATE ========== //

    /// @notice Minimum auction duration in seconds
    uint48 public minAuctionDuration;

    /// @notice Constant for percentages
    /// @dev    1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint48 internal constant _ONE_HUNDRED_PERCENT = 100_000;

    /// @notice General information pertaining to auction lots
    mapping(uint96 id => Lot lot) public lotData;

    // ========== ATOMIC AUCTIONS ========== //

    /// @notice     Purchase tokens from an auction lot
    /// @dev        The implementing function should handle the following:
    ///             - Validate the purchase parameters
    ///             - Store the purchase data
    ///
    /// @param      lotId_             The lot id
    /// @param      amount_         The amount of quote tokens to purchase
    /// @param      auctionData_    The auction-specific data
    /// @return     payout          The amount of payout tokens to receive
    /// @return     auctionOutput   The auction-specific output
    function purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external virtual returns (uint256 payout, bytes memory auctionOutput);

    // ========== BATCH AUCTIONS ========== //

    /// @notice     Bid on an auction lot
    /// @dev        The implementing function should handle the following:
    ///             - Validate the bid parameters
    ///             - Store the bid data
    ///
    /// @param      lotId_          The lot id
    /// @param      bidder_         The bidder of the purchased tokens
    /// @param      recipient_      The recipient of the purchased tokens
    /// @param      referrer_       The referrer of the bid
    /// @param      amount_         The amount of quote tokens to bid
    /// @param      auctionData_    The auction-specific data
    function bid(
        uint96 lotId_,
        address bidder_,
        address recipient_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external virtual returns (uint96 bidId);

    /// @notice     Cancel a bid
    /// @dev        The implementing function should handle the following:
    ///             - Validate the bid parameters
    ///             - Authorize `bidder_`
    ///             - Update the bid data
    ///
    /// @param      lotId_      The lot id
    /// @param      bidId_      The bid id
    /// @param      bidder_     The bidder of the purchased tokens
    /// @return     bidAmount   The amount of quote tokens to refund
    function cancelBid(
        uint96 lotId_,
        uint96 bidId_,
        address bidder_
    ) external virtual returns (uint256 bidAmount);

    /// @notice     Settle a batch auction lot with on-chain storage and settlement
    /// @dev        The implementing function should handle the following:
    ///             - Validate the lot parameters
    ///             - Determine the winning bids
    ///             - Update the lot data
    ///
    /// @param      lotId_          The lot id
    /// @return     winningBids_    The winning bids
    /// @return     auctionOutput_  The auction-specific output
    function settle(uint96 lotId_)
        external
        virtual
        returns (Bid[] memory winningBids_, bytes memory auctionOutput_);

    // ========== AUCTION MANAGEMENT ========== //

    /// @notice     Create an auction lot
    ///
    /// @param      lotId_                  The lot id
    /// @param      params_                 The auction parameters
    /// @param      quoteTokenDecimals_     The quote token decimals
    /// @param      baseTokenDecimals_      The base token decimals
    /// @return     prefundingRequired      Whether or not prefunding is required
    /// @return     capacity                The capacity of the lot
    function auction(
        uint96 lotId_,
        AuctionParams memory params_,
        uint8 quoteTokenDecimals_,
        uint8 baseTokenDecimals_
    ) external virtual returns (bool prefundingRequired, uint256 capacity);

    /// @notice     Cancel an auction lot
    /// @dev        The implementing function should handle the following:
    ///             - Validate the lot parameters
    ///             - Update the lot data
    ///             - Return the remaining capacity (so that the AuctionHouse can refund the owner)
    ///
    /// @param      lotId_              The lot id
    function cancelAuction(uint96 lotId_) external virtual;

    // ========== AUCTION INFORMATION ========== //

    function payoutFor(uint96 lotId_, uint256 amount_) public view virtual returns (uint256);

    function priceFor(uint96 lotId_, uint256 payout_) public view virtual returns (uint256);

    function maxPayout(uint96 lotId_) public view virtual returns (uint256);

    function maxAmountAccepted(uint96 lotId_) public view virtual returns (uint256);

    /// @notice     Returns whether the auction is currently accepting bids or purchases
    /// @dev        The implementing function should handle the following:
    ///             - Return true if the lot is accepting bids/purchases
    ///             - Return false if the lot has ended, been cancelled, or not started yet
    ///
    /// @param      lotId_  The lot id
    /// @return     bool    Whether or not the lot is active
    function isLive(uint96 lotId_) public view virtual returns (bool);

    /// @notice     Returns whether the auction has ended
    /// @dev        The implementing function should handle the following:
    ///             - Return true if the lot is not accepting bids/purchases and will not at any point
    ///             - Return false if the lot hasn't started or is actively accepting bids/purchases
    ///
    /// @param      lotId_  The lot id
    /// @return     bool    Whether or not the lot is active
    function hasEnded(uint96 lotId_) public view virtual returns (bool);

    /// @notice     Get the remaining capacity of a lot
    /// @dev        The implementing function should handle the following:
    ///             - Return the remaining capacity of the lot
    ///
    /// @param      lotId_  The lot id
    /// @return     uint256 The remaining capacity of the lot
    function remainingCapacity(uint96 lotId_) external view virtual returns (uint256);

    /// @notice     Get whether or not the capacity is in quote tokens
    /// @dev        The implementing function should handle the following:
    ///             - Return true if the capacity is in quote tokens
    ///             - Return false if the capacity is in base tokens
    ///
    /// @param      lotId_  The lot id
    /// @return     bool    Whether or not the capacity is in quote tokens
    function capacityInQuote(uint96 lotId_) external view virtual returns (bool);
}

abstract contract AuctionModule is Auction, Module {
    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_) Module(auctionHouse_) {}

    // ========== AUCTION MANAGEMENT ========== //

    /// @inheritdoc Auction
    /// @dev        If the start time is zero, the auction will have a start time of the current block timestamp
    ///
    /// @dev        This function reverts if:
    ///             - the caller is not the parent of the module
    ///             - the start time is in the past
    ///             - the duration is less than the minimum
    function auction(
        uint96 lotId_,
        AuctionParams memory params_,
        uint8 quoteTokenDecimals_,
        uint8 baseTokenDecimals_
    ) external override onlyInternal returns (bool prefundingRequired, uint256 capacity) {
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
        (prefundingRequired) = _auction(lotId_, lot, params_.implParams);

        // Store lot data
        lotData[lotId_] = lot;

        return (prefundingRequired, lot.capacity);
    }

    /// @notice     Implementation-specific auction creation logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_              The lot ID
    /// @param      lot_                The lot data
    /// @param      params_             Additional auction parameters
    /// @return     prefundingRequired  Whether or not prefunding is required
    function _auction(
        uint96 lotId_,
        Lot memory lot_,
        bytes memory params_
    ) internal virtual returns (bool prefundingRequired);

    /// @notice     Cancel an auction lot
    /// @dev        Assumptions:
    ///             - The parent will refund the owner the remaining capacity
    ///             - The parent will verify that the caller is the owner
    ///
    ///             This function reverts if:
    ///             - the caller is not the parent of the module
    ///             - the lot id is invalid
    ///             - the lot has concluded
    ///
    /// @param      lotId_      The lot id
    function cancelAuction(uint96 lotId_) external override onlyInternal {
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

    // ========== ATOMIC AUCTIONS ========== //

    /// @inheritdoc Auction
    /// @dev        Implements a basic purchase function that:
    ///             - Calls implementation-specific validation logic
    ///             - Calls the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot is inactive
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should override _purchase to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Storing the purchase data
    function purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external override onlyInternal returns (uint256 payout, bytes memory auctionOutput) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotInactive(lotId_);

        // Call implementation-specific logic
        return _purchase(lotId_, amount_, auctionData_);
    }

    /// @notice     Implementation-specific purchase logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_          The lot ID
    /// @param      amount_         The amount of quote tokens to purchase
    /// @param      auctionData_    The auction-specific data
    /// @return     payout          The amount of payout tokens to receive
    /// @return     auctionOutput   The auction-specific output
    function _purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal virtual returns (uint256 payout, bytes memory auctionOutput);

    // ========== BATCH AUCTIONS ========== //

    /// @inheritdoc Auction
    /// @dev        Implements a basic bid function that:
    ///             - Calls implementation-specific validation logic
    ///             - Calls the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot has not started
    ///             - the lot has concluded
    ///             - the lot is already settled
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should override _bid to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Storing the bid data
    function bid(
        uint96 lotId_,
        address bidder_,
        address recipient_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external override onlyInternal returns (uint96 bidId) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotConcluded(lotId_);
        _revertIfLotSettled(lotId_);

        // Call implementation-specific logic
        return _bid(lotId_, bidder_, recipient_, referrer_, amount_, auctionData_);
    }

    /// @notice     Implementation-specific bid logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///             The returned `bidId` should be a unique and persistent identifier for the bid,
    ///             which can be used in subsequent calls (e.g. `cancelBid()` or `settle()`).
    ///
    /// @param      lotId_          The lot ID
    /// @param      bidder_         The bidder of the purchased tokens
    /// @param      recipient_      The recipient of the purchased tokens
    /// @param      referrer_       The referrer of the bid
    /// @param      amount_         The amount of quote tokens to bid
    /// @param      auctionData_    The auction-specific data
    /// @return     bidId           The bid ID
    function _bid(
        uint96 lotId_,
        address bidder_,
        address recipient_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal virtual returns (uint96 bidId);

    /// @inheritdoc Auction
    /// @dev        Implements a basic cancelBid function that:
    ///             - Calls implementation-specific validation logic
    ///             - Calls the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot is not active
    ///             - the lot is already settled
    ///             - the bid id is invalid
    ///             - the bid is already cancelled
    ///             - `caller_` is not the bid owner
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should override _cancelBid to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Updating the bid data
    function cancelBid(
        uint96 lotId_,
        uint96 bidId_,
        address caller_
    ) external override onlyInternal returns (uint256 bidAmount) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotConcluded(lotId_);
        _revertIfLotSettled(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);
        _revertIfNotBidOwner(lotId_, bidId_, caller_);
        _revertIfBidCancelled(lotId_, bidId_);

        // Call implementation-specific logic
        return _cancelBid(lotId_, bidId_, caller_);
    }

    /// @notice     Implementation-specific bid cancellation logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    /// @param      caller_     The caller
    /// @return     bidAmount   The amount of quote tokens to refund
    function _cancelBid(
        uint96 lotId_,
        uint96 bidId_,
        address caller_
    ) internal virtual returns (uint256 bidAmount);

    /// @inheritdoc Auction
    /// @dev        Implements a basic settle function that:
    ///             - Calls implementation-specific validation logic
    ///             - Calls the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot is still active
    ///             - the lot has already been settled
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should override _settle to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Determining the winning bids
    ///             - Updating the lot data
    function settle(uint96 lotId_)
        external
        override
        onlyInternal
        returns (Bid[] memory winningBids_, bytes memory auctionOutput_)
    {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotActive(lotId_);
        _revertIfLotSettled(lotId_);

        // Call implementation-specific logic
        return _settle(lotId_);
    }

    /// @notice     Implementation-specific lot settlement logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_          The lot ID
    /// @return     winningBids_    The winning bids
    /// @return     auctionOutput_  The auction-specific output
    function _settle(uint96 lotId_)
        internal
        virtual
        returns (Bid[] memory winningBids_, bytes memory auctionOutput_);

    // ========== AUCTION INFORMATION ========== //

    /// @inheritdoc Auction
    /// @dev        A lot is active if:
    ///             - The lot has not concluded
    ///             - The lot has started
    ///             - The lot has not sold out or been cancelled (capacity > 0)
    ///
    /// @param      lotId_  The lot ID
    /// @return     bool    Whether or not the lot is active
    function isLive(uint96 lotId_) public view override returns (bool) {
        return (
            lotData[lotId_].capacity != 0 && lotData[lotId_].conclusion > uint48(block.timestamp)
                && lotData[lotId_].start <= uint48(block.timestamp)
        );
    }

    /// @inheritdoc Auction
    function hasEnded(uint96 lotId_) public view override returns (bool) {
        return lotData[lotId_].conclusion < uint48(block.timestamp) || lotData[lotId_].capacity == 0;
    }

    /// @inheritdoc Auction
    function remainingCapacity(uint96 lotId_) external view override returns (uint256) {
        return lotData[lotId_].capacity;
    }

    /// @inheritdoc Auction
    function capacityInQuote(uint96 lotId_) external view override returns (bool) {
        return lotData[lotId_].capacityInQuote;
    }

    /// @notice    Get the lot data for a given lot ID
    ///
    /// @param     lotId_  The lot ID
    function getLot(uint96 lotId_) external view returns (Lot memory) {
        return lotData[lotId_];
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
        if (lotData[lotId_].start > uint48(block.timestamp)) revert Auction_MarketNotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` has started
    /// @dev        Should revert if the lot has started
    function _revertIfLotStarted(uint96 lotId_) internal view virtual {
        if (lotData[lotId_].start <= uint48(block.timestamp)) revert Auction_MarketActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` has not concluded
    /// @dev        Should revert if the lot has concluded
    function _revertIfLotConcluded(uint96 lotId_) internal view virtual {
        // Beyond the conclusion time
        if (lotData[lotId_].conclusion < uint48(block.timestamp)) {
            revert Auction_MarketNotActive(lotId_);
        }

        // Capacity is sold-out, or cancelled
        if (lotData[lotId_].capacity == 0) revert Auction_MarketNotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` is active
    /// @dev        Should revert if the lot is not active
    ///             Inheriting contracts can override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotInactive(uint96 lotId_) internal view virtual {
        if (!isLive(lotId_)) revert Auction_MarketNotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` is active
    /// @dev        Should revert if the lot is active
    ///             Inheriting contracts can override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotActive(uint96 lotId_) internal view virtual {
        if (isLive(lotId_)) revert Auction_MarketActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` is not settled
    /// @dev        Should revert if the lot is settled
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotSettled(uint96 lotId_) internal view virtual;

    /// @notice     Checks that the lot and bid combination is valid
    /// @dev        Should revert if the bid is invalid
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    /// @param      bidId_  The bid ID
    function _revertIfBidInvalid(uint96 lotId_, uint96 bidId_) internal view virtual;

    /// @notice     Checks that `caller_` is the bid owner
    /// @dev        Should revert if `caller_` is not the bid owner
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    /// @param      caller_     The caller
    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint96 bidId_,
        address caller_
    ) internal view virtual;

    /// @notice     Checks that the bid is not cancelled
    /// @dev        Should revert if the bid is cancelled
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    function _revertIfBidCancelled(uint96 lotId_, uint96 bidId_) internal view virtual;
}
