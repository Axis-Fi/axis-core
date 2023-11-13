/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Auctioneer, IAggregator, Authority} from "src/auctioneers/bases/Auctioneer.sol";
import {IMaxPayoutAuctioneer} from "src/interfaces/IMaxPayoutAuctioneer.sol";

abstract contract MaxPayoutAuctioneer is Auctioneer, IMaxPayoutAuctioneer {
    /* ========== ERRORS ========== */
    error Auctioneer_InitialPriceLessThanMin();

    /* ========== STATE ========== */

    /// @notice Minimum deposit interval for a market
    uint48 public minDepositInterval;

    mapping(uint256 id => StyleData style) public styleData;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IAggregator aggregator_,
        address guardian_,
        Authority authority_
    ) Auctioneer(aggregator_, guardian_, authority_) {
        minDepositInterval = 1 hours;
    }

    /* ========== MARKET FUNCTIONS ========== */

    function _createMarket(
        uint256 id_,
        CoreData memory core_,
        bytes calldata params_
    ) internal override {
        // Decode provided params
        (uint48 depositInterval, bytes calldata params) = abi.decode(params_, (uint48, bytes));

        // Validate that deposit interval is in-bounds
        uint48 duration = core_.conclusion - core_.start;
        if (depositInterval < MIN_DEPOSIT_INTERVAL || depositInterval > duration)
            revert Auctioneer_InvalidParams();

        // Set style data
        StyleData memory style = styleData[id_];
        style.depositInterval = depositInterval;
        style.scale = 10 ** core_.quoteToken.decimals();

        // Call internal __createMarket function to store implementation-specific data
        __createMarket(id, core_, style, params);

        // Set max payout (depends on marketPrice being available so must be done after __createMarket)
        style.maxPayout = _payoutCapacity(core_).mulDiv(depositInterval, duration);
    }

    /// @dev implementation-specific market creation logic can be inserted by overriding this function
    function __createMarket(
        uint256 id_,
        CoreData memory core_,
        StyleData memory style_,
        bytes memory params_
    ) internal virtual;

    /* ========== TELLER FUNCTIONS ========== */

    function _purchase(uint256 id_, uint256 amount_) internal returns (uint256) {
        // Get payout from implementation-specific purchase logic
        uint256 payout = __purchaseBond(id_, amount_);

        // Check that payout is less than or equal to max payout
        if (payout > styleData[id_].maxPayout) revert Auctioneer_MaxPayoutExceeded();

        return payout;
    }

    /// @dev implementation-specific purchase logic can be inserted by overriding this function
    function __purchase(uint256 id_, uint256 amount_) internal virtual returns (uint256);

    /* ========== ADMIN FUNCTIONS ========== */

    /// @inheritdoc IMaxPayoutAuctioneer
    function setMinDepositInterval(uint48 depositInterval_) external override requiresAuth {
        // Restricted to authorized addresses

        // Require min deposit interval to be less than minimum market duration and at least 1 hour
        if (depositInterval_ > minMarketDuration || depositInterval_ < 1 hours)
            revert Auctioneer_InvalidParams();

        minDepositInterval = depositInterval_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function _payoutCapacity(CoreData memory core_) internal view returns (uint256) {
        // Calculate capacity in terms of payout tokens
        // If capacity is in quote tokens, convert to payout tokens with market price
        // Otherwise, return capacity as-is
        return
            core_.capacityInQuote
                ? core_.capacity.mulDiv(styleData[id_].scale, marketPrice(id_))
                : core_.capacity;
    }

    /// @inheritdoc IMaxPayoutAuctioneer
    function marketPrice(uint256 id_) public view virtual returns (uint256);

    /// @inheritdoc IMaxPayoutAuctioneer
    function marketScale(uint256 id_) external view override returns (uint256) {
        return styleData[id_].scale;
    }

    /// @inheritdoc IMaxPayoutAuctioneer
    function maxAmountAccepted(
        uint256 id_,
        address referrer_
    ) external view override returns (uint256) {
        // Calculate maximum amount of quote tokens that correspond to max bond size
        // Maximum of the maxPayout and the remaining capacity converted to quote tokens
        CoreData memory core = coreData[id_];
        StyleData memory style = styleData[id_];
        uint256 price = marketPrice(id_);
        uint256 quoteCapacity = core.capacityInQuote
            ? core.capacity
            : core.capacity.mulDiv(price, style.scale);
        uint256 maxQuote = style.maxPayout.mulDiv(price, style.scale);
        uint256 amountAccepted = quoteCapacity < maxQuote ? quoteCapacity : maxQuote;

        // Take into account teller fees and return
        // Estimate fee based on amountAccepted. Fee taken will be slightly larger than
        // this given it will be taken off the larger amount, but this avoids rounding
        // errors with trying to calculate the exact amount.
        // Therefore, the maxAmountAccepted is slightly conservative.
        uint256 estimatedFee = amountAccepted.mulDiv(
            core.teller.getFee(referrer_),
            ONE_HUNDRED_PERCENT
        );

        return amountAccepted + estimatedFee;
    }

    /// @inheritdoc IMaxPayoutAuctioneer
    function maxPayout(uint256 id_) public view override returns (uint256) {
        // Convert capacity to payout token units for comparison with max payout
        uint256 capacity = _payoutCapacity(coreData[id_]);

        // Cap max payout at the remaining capacity
        return styleData[id_].maxPayout > capacity ? capacity : styleData[id_].maxPayout;
    }
}
