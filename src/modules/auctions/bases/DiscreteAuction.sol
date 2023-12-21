/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "src/modules/auctions/bases/AtomicAuction.sol";

abstract contract DiscreteAuction {
    /* ========== ERRORS ========== */
    error Auction_MaxPayoutExceeded();

    /* ========== DATA STRUCTURES ========== */
    struct StyleData {
        uint48 depositInterval; // target interval between deposits
        uint256 maxPayout; // maximum payout for a single purchase
        uint256 scale; // stored scale for auction price
    }

    /* ========== STATE ========== */

    /// @notice Minimum deposit interval for a discrete auction
    uint48 public minDepositInterval;

    mapping(uint256 lotId => StyleData style) public styleData;

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice Set the minimum deposit interval
    /// @notice Access controlled
    /// @param depositInterval_ Minimum deposit interval in seconds
    function setMinDepositInterval(uint48 depositInterval_) external;

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice             Calculate current auction price of base token in quote tokens
    /// @param id_          ID of auction
    /// @return             Price for auction in configured decimals
    function auctionPrice(uint256 id_) external view returns (uint256);

    /// @notice             Scale value to use when converting between quote token and base token amounts with auctionPrice()
    /// @param id_          ID of auction
    /// @return             Scaling factor for auction in configured decimals
    function auctionScale(uint256 id_) external view returns (uint256);

    function maxPayout(uint256 id_) external view returns(uint256);
}

abstract contract DiscreteAuctionModule is AtomicAuctionModule, DiscreteAuction {

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address auctionHouse_
    ) AtomicAuctionModule(auctionHouse_) {
        minDepositInterval = 1 hours;
    }

    /* ========== MARKET FUNCTIONS ========== */

    function _auction(
        uint256 id_,
        LotData memory lot_,
        bytes calldata params_
    ) internal override {
        // Decode provided params
        (uint48 depositInterval, bytes calldata params) = abi.decode(params_, (uint48, bytes));

        // Validate that deposit interval is in-bounds
        uint48 duration = lot_.conclusion - lot_.start;
        if (depositInterval < MIN_DEPOSIT_INTERVAL || depositInterval > duration)
            revert Auctioneer_InvalidParams();

        // Set style data
        StyleData memory style = styleData[id_];
        style.depositInterval = depositInterval;
        style.scale = 10 ** lot_.quoteToken.decimals();

        // Call internal __createMarket function to store implementation-specific data
        __createMarket(id, lot_, style, params);

        // Set max payout (depends on auctionPrice being available so must be done after __createMarket)
        style.maxPayout = _baseCapacity(lot_).mulDiv(depositInterval, duration);
    }

    /// @dev implementation-specific auction creation logic can be inserted by overriding this function
    function __auction(
        uint256 id_,
        LotData memory lot_,
        StyleData memory style_,
        bytes memory params_
    ) internal virtual;

    /* ========== TELLER FUNCTIONS ========== */

    function _purchase(uint256 id_, uint256 amount_) internal returns (uint256) {
        // Get payout from implementation-specific purchase logic
        uint256 payout = __purchaseBond(id_, amount_);

        // Check that payout is less than or equal to max payout
        if (payout > styleData[id_].maxPayout) revert Auction_MaxPayoutExceeded();

        return payout;
    }

    /// @dev implementation-specific purchase logic can be inserted by overriding this function
    function __purchase(uint256 id_, uint256 amount_) internal virtual returns (uint256);

    /* ========== ADMIN FUNCTIONS ========== */

    /// @inheritdoc DiscreteAuction
    function setMinDepositInterval(uint48 depositInterval_) external override onlyParent {
        // Restricted to authorized addresses

        // Require min deposit interval to be less than minimum auction duration and at least 1 hour
        if (depositInterval_ > minAuctionDuration || depositInterval_ < 1 hours)
            revert Auction_InvalidParams();

        minDepositInterval = depositInterval_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function _baseCapacity(LotData memory lot_) internal view returns (uint256) {
        // Calculate capacity in terms of base tokens
        // If capacity is in quote tokens, convert to base tokens with auction price
        // Otherwise, return capacity as-is
        return
            lot_.capacityInQuote
                ? lot_.capacity.mulDiv(styleData[id_].scale, auctionPrice(id_))
                : lot_.capacity;
    }

    /// @inheritdoc DiscreteAuction    
    function auctionPrice(uint256 id_) public view virtual returns (uint256);

    /// @inheritdoc DiscreteAuction
    function auctionScale(uint256 id_) external view override returns (uint256) {
        return styleData[id_].scale;
    }

    /// @dev This function is gated by onlyParent because it does not include any fee logic, which is applied in the parent contract
    function payoutFor(uint256 id_, uint256 amount_) public view override onlyParent returns (uint256) {
        // TODO handle payout greater than max payout - revert?
        
        // Calculate payout for amount of quote tokens
        return amount_.mulDiv(styleData[id_].scale, auctionPrice(id_));
    }

    /// @dev This function is gated by onlyParent because it does not include any fee logic, which is applied in the parent contract
    function priceFor(uint256 id_, uint256 payout_) public view override onlyParent returns (uint256) {
        // TODO handle payout greater than max payout - revert?

        // Calculate price for payout in quote tokens
        return payout_.mulDiv(auctionPrice(id_), styleData[id_].scale);
    }

    /// @dev This function is gated by onlyParent because it does not include any fee logic, which is applied in the parent contract
    function maxAmountAccepted(uint256 id_) external view override onlyParent returns (uint256) {
        // Calculate maximum amount of quote tokens that correspond to max bond size
        // Maximum of the maxPayout and the remaining capacity converted to quote tokens
        LotData memory lot = lotData[id_];
        StyleData memory style = styleData[id_];
        uint256 price = auctionPrice(id_);
        uint256 quoteCapacity = lot.capacityInQuote
            ? lot.capacity
            : lot.capacity.mulDiv(price, style.scale);
        uint256 maxQuote = style.maxPayout.mulDiv(price, style.scale);
        uint256 amountAccepted = quoteCapacity < maxQuote ? quoteCapacity : maxQuote;

        return amountAccepted;
    }

    /// @notice             Calculate max payout of the auction in base tokens
    /// @dev                Returns a dynamically calculated payout or the maximum set by the creator, whichever is less.
    /// @param id_          ID of auction
    /// @return             Current max payout for the auction in base tokens
    /// @dev This function is gated by onlyParent because it does not include any fee logic, which is applied in the parent contract
    function maxPayout(uint256 id_) public view override onlyParent returns (uint256) {
        // Convert capacity to base token units for comparison with max payout
        uint256 capacity = _baseCapacity(lotData[id_]);

        // Cap max payout at the remaining capacity
        return styleData[id_].maxPayout > capacity ? capacity : styleData[id_].maxPayout;
    }
}