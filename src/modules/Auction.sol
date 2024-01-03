/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "src/modules/Modules.sol";

abstract contract Auction {

    /* ========== ERRORS ========== */

    error Auction_OnlyMarketOwner();
    error Auction_MarketNotActive();
    error Auction_AmountLessThanMinimum();
    error Auction_NotEnoughCapacity();
    error Auction_InvalidParams();
    error Auction_NotAuthorized();
    error Auction_NotImplemented();

    /* ========== EVENTS ========== */

    event AuctionCreated(
        uint256 indexed id,
        address indexed payoutToken,
        address indexed quoteToken
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

    struct Bid {
        address bidder;
        uint256 amount;
        uint256 minAmountOut;
        bytes32 param; // optional implementation-specific parameter for the bid
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
    uint48 internal constant ONE_HUNDRED_PERCENT = 1e5;

    /// @notice General information pertaining to auction lots
    mapping(uint256 id => Lot lot) public lotData;

    // ========== ATOMIC AUCTIONS ========== //

    function purchase(uint256 id_, uint256 amount_, bytes calldata auctionData_) external virtual returns (uint256 payout, bytes memory auctionOutput);

    // ========== BATCH AUCTIONS ========== //

    // On-chain auction variant
    function bid(uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_) external virtual;

    function settle(uint256 id_) external virtual returns (uint256[] memory amountsOut);

    // Off-chain auction variant
    // TODO use solady data packing library to make bids smaller on the actual module to store?
    function settle(uint256 id_, Bid[] memory bids_) external virtual returns (uint256[] memory amountsOut);

    // ========== AUCTION MANAGEMENT ========== //

    function auction(uint256 id_, AuctionParams memory params_) external virtual;

    function cancel(uint256 id_) external virtual;

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

    function auction(uint256 id_, AuctionParams memory params_) external override onlyParent {
        // Start time must be zero or in the future
        if (params_.start > 0 && params_.start < uint48(block.timestamp))
            revert Auction_InvalidParams();

        // Duration must be at least min duration
        if (params_.duration < minAuctionDuration) revert Auction_InvalidParams();


        // Create core market data
        Lot memory lot;
        lot.start = params_.start == 0 ? uint48(block.timestamp) : params_.start;
        lot.conclusion = lot.start + params_.duration;
        lot.capacityInQuote = params_.capacityInQuote;
        lot.capacity = params_.capacity;

        // Call internal createAuction function to store implementation-specific data
        _auction(id_, lot, params_.implParams);

        // Store lot data
        lotData[id_] = lot;
    }

    /// @dev implementation-specific auction creation logic can be inserted by overriding this function
    function _auction(
        uint256 id_,
        Lot memory lot_,
        bytes memory params_
    ) internal virtual returns (uint256);

    /// @dev Owner is stored in the Routing information on the AuctionHouse, so we check permissions there
    function cancel(uint256 id_) external override onlyParent {
        Lot storage lot = lotData[id_];
        lot.conclusion = uint48(block.timestamp);
        lot.capacity = 0;

        // Call internal closeAuction function to update any other required parameters
        _cancel(id_);
    }

    function _cancel(uint256 id_) internal virtual;

    // ========== AUCTION INFORMATION ========== //

    // TODO does this need to change for batch auctions?
    function isLive(uint256 id_) public view override returns (bool) {
        return (lotData[id_].capacity != 0 &&
            lotData[id_].conclusion > uint48(block.timestamp) &&
            lotData[id_].start <= uint48(block.timestamp));
    }

    function remainingCapacity(uint256 id_) external view override returns (uint256) {
        return lotData[id_].capacity;
    }
}