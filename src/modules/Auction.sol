/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";

abstract contract Auction {
    /* ========== ERRORS ========== */

    error Auction_MarketNotActive(uint96 lotId);

    error Auction_InvalidStart(uint48 start_, uint48 minimum_);

    error Auction_InvalidDuration(uint48 duration_, uint48 minimum_);

    error Auction_InvalidLotId(uint96 lotId);

    error Auction_InvalidBidId(uint96 lotId, uint256 bidId);

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
    /// @notice Core data for an auction lot
    struct Lot {
        uint48 start; // timestamp when market starts
        uint48 conclusion; // timestamp when market no longer offered
        bool capacityInQuote; // capacity limit is in payment token (true) or in payout (false, default)
        uint256 capacity; // capacity remaining
        uint256 sold; // payout tokens out
        uint256 purchased; // quote tokens in
    }

    // TODO pack if we anticipate on-chain auction variants
    struct Bid {
        address bidder;
        address recipient;
        address referrer;
        uint256 amount;
        uint256 minAmountOut;
        bytes auctionParam; // optional implementation-specific parameter for the bid
    }

    struct AuctionParams {
        uint48 start;
        uint48 duration;
        bool capacityInQuote;
        uint256 capacity;
        bytes implParams; // abi-encoded params for specific auction implementations
    }

    // ========= STATE ========== //

    /// @notice Minimum auction duration in seconds
    uint48 public minAuctionDuration;

    // 1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint48 internal constant _ONE_HUNDRED_PERCENT = 1e5;

    /// @notice General information pertaining to auction lots
    mapping(uint256 id => Lot lot) public lotData;

    // ========== ATOMIC AUCTIONS ========== //

    function purchase(
        uint96 id_,
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
    ) external virtual returns (uint256 bidId);

    /// @notice     Cancel a bid
    /// @dev        The implementing function should handle the following:
    ///             - Validate the bid parameters
    ///             - Authorize `bidder_`
    ///             - Update the bid data
    ///
    /// @param      lotId_      The lot id
    /// @param      bidId_      The bid id
    /// @param      bidder_     The bidder of the purchased tokens
    function cancelBid(uint96 lotId_, uint256 bidId_, address bidder_) external virtual;

    /// @notice     Claim a refund for a bid
    /// @dev        The implementing function should handle the following:
    ///             - Validate the bid parameters
    ///             - Authorize `bidder_`
    ///             - Update the bid data
    ///
    /// @param      lotId_          The lot id
    /// @param      bidId_          The bid id
    /// @param      bidder_         The bidder of the purchased tokens
    /// @return     refundAmount    The amount of quote tokens refunded
    function claimRefund(
        uint96 lotId_,
        uint256 bidId_,
        address bidder_
    ) external virtual returns (uint256 refundAmount);

    /// @notice     Settle a batch auction with the provided bids
    /// @notice     This function is used for on-chain storage of bids and external settlement
    ///
    /// @param      lotId_              Lot id
    /// @param      winningBids_        Winning bids
    /// @param      settlementProof_    Proof of settlement validity
    /// @param      settlementData_     Settlement data
    /// @return     amountsOut          Amount out for each bid
    /// @return     auctionOutput       Auction-specific output
    function settle(
        uint96 lotId_,
        Bid[] calldata winningBids_,
        bytes calldata settlementProof_,
        bytes calldata settlementData_
    ) external virtual returns (uint256[] memory amountsOut, bytes memory auctionOutput);

    // ========== AUCTION MANAGEMENT ========== //

    // TODO NatSpec comments
    // TODO validate function

    /// @notice     Create an auction lot
    ///
    /// @param      lotId_      The lot id
    /// @param      params_     The auction parameters
    /// @return     prefundingRequired  Whether or not prefunding is required
    /// @return     capacity            The capacity of the lot
    function auction(
        uint96 lotId_,
        AuctionParams memory params_
    ) external virtual returns (bool prefundingRequired, uint256 capacity);

    function cancelAuction(uint96 id_) external virtual;

    // ========== AUCTION INFORMATION ========== //

    function payoutFor(uint256 id_, uint256 amount_) public view virtual returns (uint256);

    function priceFor(uint256 id_, uint256 payout_) public view virtual returns (uint256);

    function maxPayout(uint256 id_) public view virtual returns (uint256);

    function maxAmountAccepted(uint256 id_) public view virtual returns (uint256);

    function isLive(uint256 id_) public view virtual returns (bool);

    function remainingCapacity(uint256 id_) external view virtual returns (uint256);
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
        AuctionParams memory params_
    ) external override onlyParent returns (bool prefundingRequired, uint256 capacity) {
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
        lot.capacityInQuote = params_.capacityInQuote;
        lot.capacity = params_.capacity;

        // Call internal createAuction function to store implementation-specific data
        (prefundingRequired) = _auction(lotId_, lot, params_.implParams);

        // Cannot pre-fund if capacity is in quote token
        if (prefundingRequired && lot.capacityInQuote) revert Auction_InvalidParams();

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
    /// @dev        Owner is stored in the Routing information on the AuctionHouse, so we check permissions there
    /// @dev        This function reverts if:
    ///             - the caller is not the parent of the module
    ///             - the lot id is invalid
    ///             - the lot is not active
    ///
    /// @param      lotId_      The lot id
    function cancelAuction(uint96 lotId_) external override onlyParent {
        Lot storage lot = lotData[lotId_];

        // Invalid lot
        if (lot.start == 0) revert Auction_InvalidLotId(lotId_);

        // Inactive lot
        if (lot.capacity == 0) revert Auction_MarketNotActive(lotId_);

        lot.conclusion = uint48(block.timestamp);
        lot.capacity = 0;

        // Call internal closeAuction function to update any other required parameters
        _cancelAuction(lotId_);
    }

    function _cancelAuction(uint96 id_) internal virtual;

    // ========== AUCTION INFORMATION ========== //

    // TODO does this need to change for batch auctions?
    function isLive(uint256 id_) public view override returns (bool) {
        return (
            lotData[id_].capacity != 0 && lotData[id_].conclusion > uint48(block.timestamp)
                && lotData[id_].start <= uint48(block.timestamp)
        );
    }

    function remainingCapacity(uint256 id_) external view override returns (uint256) {
        return lotData[id_].capacity;
    }

    // ========== MODIFIERS ========== //

    /// @notice     Checks that the lot ID is valid
    /// @dev        Reverts if the lot ID is invalid
    ///
    /// @param      lotId_  The lot identifier
    modifier isLotValid(uint96 lotId_) {
        if (lotData[lotId_].start == 0) revert Auction_InvalidLotId(lotId_);
        _;
    }

    /// @notice     Checks that the lot is active
    /// @dev        Reverts if the lot is not active
    ///
    /// @param      lotId_  The lot identifier
    modifier isLotActive(uint96 lotId_) {
        Lot memory lot = lotData[lotId_];
        if (
            lot.capacity == 0 || lot.conclusion < uint48(block.timestamp)
                || lot.start > block.timestamp
        ) revert Auction_MarketNotActive(lotId_);
        _;
    }
}
