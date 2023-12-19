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

    /// @param approval_ - (Optional) Permit approval signature for the quoteToken
    function purchase(address recipient_, address referrer_, uint256 id_, uint256 amount_, bytes calldata auctionData_, bytes calldata approval_) external virtual returns (uint256 payout);

    // ========== BATCH AUCTIONS ========== //

    // On-chain auction variant
    function bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_) external virtual;

    function settle(uint256 id_) external virtual returns (uint256[] memory amountsOut);

    // Off-chain auction variant
    // TODO use solady data packing library to make bids smaller on the actual module to store
    function settle(uint256 id_, Bid[] memory bids_) external virtual returns (uint256[] memory amountsOut);

    // ========== AUCTION MANAGEMENT ========== //

    function createAuction(uint256 id_, address owner_, AuctionParams memory params_) external virtual;

    function cancelAuction(uint256 id_) external virtual;

    // ========== AUCTION INFORMATION ========== //

    function payoutFor(uint256 id_, uint256 amount_) public view virtual returns (uint256);

    function priceFor(uint256 id_, uint256 payout_) public view virtual returns (uint256);

    function maxPayout(uint256 id_) public view virtual returns (uint256);

    function maxAmountAccepted(uint256 id_) public view virtual returns (uint256);

    function isLive(uint256 id_) public view virtual returns (bool);

    function ownerOf(uint256 id_) external view virtual returns (address);

    function remainingCapacity(uint256 id_) external view virtual returns (uint256); 
}

abstract contract AuctionModule is Auction, Module {

    // ========== AUCTION EXECUTION ========== //

    function purchase(uint256 id_, uint256 amount_, bytes calldata auctionData_) external override onlyParent returns (uint256 payout, bytes memory auctionOutput) {
        Lot storage lot = lotData[id_];

        // Check if market is live, if not revert
        if (!isLive(id_)) revert Auction_MarketNotActive();

        // Get payout from implementation-specific auction logic
        payout = _purchase(id_, amount_);

        // Update Capacity

        // Capacity is either the number of payout tokens that the market can sell
        // (if capacity in quote is false),
        //
        // or the number of quote tokens that the market can buy
        // (if capacity in quote is true)

        // If amount/payout is greater than capacity remaining, revert
        if (lot.capacityInQuote ? amount_ > lot.capacity : payout > lot.capacity)
            revert Auction_NotEnoughCapacity();
        // Capacity is decreased by the deposited or paid amount
        lot.capacity -= lot.capacityInQuote ? amount_ : payout;

        // Markets keep track of how many quote tokens have been
        // purchased, and how many payout tokens have been sold
        lot.purchased += amount_;
        lot.sold += payout;
    }

    /// @dev implementation-specific purchase logic can be inserted by overriding this function
    function _purchase(
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_
    ) internal virtual returns (uint256);

    /// @notice Settle a batch auction with the provided bids
    function settle(uint256 id_, Bid[] memory bids_) external override onlyParent returns (uint256[] memory amountsOut) {
        Lot storage lot = lotData[id_];

        // Must be past the conclusion time to settle
        if (uint48(block.timestamp) < lotData[id_].conclusion) revert Auction_NotConcluded();

        // Bids must not be greater than the capacity
        uint256 len = bids_.length;
        uint256 sum;
        if (lot.capacityInQuote) {
            for (uint256 i; i < len; i++) {
                sum += bids_[i].amount;
            }
            if (sum > lot.capacity) revert Auction_NotEnoughCapacity();
        } else {
            for (uint256 i; i < len; i++) {
                sum += bids_[i].minAmountOut;
            }
            if (sum > lot.capacity) revert Auction_NotEnoughCapacity();
        }

        // TODO other generic validation?
        // Check approvals in the Auctioneer since it handles token transfers

        // Get amounts out from implementation-specific auction logic
        amountsOut = _settle(id_, bids_);
    }

    // ========== AUCTION MANAGEMENT ========== //

    function auction(uint256 id_, address owner_, AuctionParams memory params_) external override onlyParent {
        // Start time must be zero or in the future
        if (params_.start > 0 && params_.start < uint48(block.timestamp))
            revert Auction_InvalidParams();

        // Duration must be at least min duration
        if (params_.duration < minAuctionDuration) revert Auction_InvalidParams();

        // Ensure token decimals are in-bounds
        {
            uint8 payoutTokenDecimals = params_.payoutToken.decimals();
            uint8 quoteTokenDecimals = params_.quoteToken.decimals();

            if (payoutTokenDecimals < 6 || payoutTokenDecimals > 18)
                revert Auction_InvalidParams();
            if (quoteTokenDecimals < 6 || quoteTokenDecimals > 18)
                revert Auction_InvalidParams();
        }

        // Create core market data
        Lot memory lot;
        lot.owner = params_.owner; // TODO: this needs to be set with msg.sender further up in the stack to avoid allowing creating a market for someone else
        lot.start = params_.start == 0 ? uint48(block.timestamp) : params_.start;
        lot.conclusion = lot.start + params_.duration;
        lot.payoutToken = params_.payoutToken;
        lot.quoteToken = params_.quoteToken;
        lot.hooks = params_.hooks;
        lot.allowlist = params_.allowlist;
        lot.capacityInQuote = params_.capacityInQuote;
        lot.capacity = params_.capacity;

        // Register market on allowlist, if applicable
        if (address(params_.allowlist) != address(0)) {
            params_.allowlist.registerMarket(id_, params_.allowlistParams);
        }

        // Store lot data
        lotData[id_] = lot;

        // Call internal createAuction function to store implementation-specific data
        _auction(id_, lot, params_.implParams);
    }

    /// @dev implementation-specific auction creation logic can be inserted by overriding this function
    function _auction(
        uint256 id_,
        Lot memory lot_,
        bytes calldata params_
    ) internal returns (uint256);

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

    function ownerOf(uint256 id_) external view override returns (address) {
        return lotData[id_].owner;
    }

    function remainingCapacity(uint256 id_) external view override returns (uint256) {
        return lotData[id_].capacity;
    }
}