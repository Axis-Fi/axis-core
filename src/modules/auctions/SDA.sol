/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {IMaxPayoutAuctioneer} from "src/interfaces/IMaxPayoutAuctioneer.sol";

interface ISequentialDutchAuctioneer is IMaxPayoutAuctioneer {
    /// @notice Auction pricing data
    struct AuctionData {
        uint256 equilibriumPrice; // price at which the auction is balanced
        uint256 minPrice; // minimum price for the auction
        uint48 decaySpeed; // market price decay speed (discount achieved over a target deposit interval)
        bool tuning; // whether or not the auction tunes the equilibrium price
    }

    /// @notice Data needed for tuning equilibrium price
    struct TuneData {
        uint48 lastTune; // last timestamp when control variable was tuned
        uint48 tuneInterval; // frequency of tuning
        uint48 tuneAdjustmentDelay; // time to implement downward tuning adjustments
        uint48 tuneGain; // parameter that controls how aggressive the tuning mechanism is, provided as a percentage with 3 decimals, i.e. 1% = 1_000
        uint256 tuneIntervalCapacity; // capacity expected to be used during a tuning interval
        uint256 tuneBelowCapacity; // capacity that the next tuning will occur at
    }

    /// @notice Equilibrium price adjustment data
    struct Adjustment {
        uint256 change;
        uint48 lastAdjustment;
        uint48 timeToAdjusted; // how long until adjustment is complete
        bool active;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    // TODO determine if we should have minimum values for tune parameters

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice             Calculate current market price of payout token in quote tokens
    /// @param id_          ID of market
    /// @return             Price for market in configured decimals (see MarketParams)
    /// @dev price is derived from the equation
    //
    // p(t) = max(min_p, p_eq * (1 + k * r(t)))
    //
    // where
    // p: price
    // min_p: minimum price
    // p_eq: equilibrium price
    //
    // k: decay speed
    // k = l / i_d * t_d
    // where
    // l: market length
    // i_d: deposit interval
    // t_d: target interval discount
    //
    // r(t): percent difference of expected capacity and actual capacity at time t
    // r(t) = (ec(t) - c(t)) / ic
    // where
    // ec(t): expected capacity at time t (assumes capacity is expended linearly over the duration)
    // ec(t) = ic * (l - t) / l
    // c(t): capacity remaining at time t
    // ic = initial capacity
    //
    // if price is below minimum price, minimum price is returned
    function marketPrice(uint256 id_) external view override returns (uint256);
}

import {MaxPayoutAuctioneer, IAggregator, Authority} from "src/auctioneers/bases/MaxPayoutAuctioneer.sol";
import {ISequentialDutchAuctioneer} from "src/interfaces/ISequentialDutchAuctioneer.sol";

contract SequentialDutchAuctioneer is MaxPayoutAuctioneer, ISequentialDutchAuctioneer {
    /* ========== STATE ========== */

    mapping(uint256 id => AuctionData) public auctionData;
    mapping(uint256 id => TuneData) public tuneData;
    mapping(uint256 id => Adjustment) public adjustments;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IAggregator aggregator_,
        address guardian_,
        Authority authority_
    ) MaxPayoutAuctioneer(aggregator_, guardian_, authority_) {}

    /* ========== MARKET FUNCTIONS ========== */

    function __createMarket(
        uint256 id_,
        CoreData memory core_,
        StyleData memory style_,
        bytes memory params_
    ) internal override {
        // Decode provided params
        // TODO - should we use a struct for this? that way it can be specified in the interface
        (
            uint256 initialPrice,
            uint256 minPrice,
            uint48 targetIntervalDiscount,
            bool tuning,
            uint48 tuneInterval,
            uint48 tuneAdjustmentDelay,
            uint48 tuneGain
        ) = abi.decode(params_, (uint256, uint256, uint48, bool, uint48, uint48, uint48));

        // Validate auction data
        if (initialPrice == 0) revert Auctioneer_InvalidParams();
        if (initialPrice < minPrice) revert Auctioneer_InitialPriceLessThanMin();
        if (targetIntervalDiscount >= ONE_HUNDRED_PERCENT) revert Auctioneer_InvalidParams();

        // Set auction data
        uint48 duration = core_.conclusion - core_.start;

        AuctionData storage auction = auctionData[id_];
        auction.equilibriumPrice = initialPrice;
        auction.minPrice = minPrice;
        auction.decaySpeed = (duration * targetIntervalDiscount) / style_.depositInterval;
        auction.tuning = tuning;

        // Check if tuning is enabled
        if (tuning) {
            // Tune interval must be at least the deposit interval
            // and atleast the minimum global tune interval
            if (tuneInterval < style_.depositInterval || tuneInterval < minTuneInterval)
                revert Auctioneer_InvalidParams();

            // Tune adjustment delay must be less than or equal to the tune interval
            if (tuneAdjustmentDelay > tuneInterval) revert Auctioneer_InvalidParams();

            // Set tune data
            TuneData storage tune = tuneData[id_];
            tune.lastTune = uint48(block.timestamp);
            tune.tuneInterval = tuneInterval;
            tune.tuneAdjustmentDelay = tuneAdjustmentDelay;
            tune.tuneIntervalCapacity = core_.capacity.mulDiv(tuneInterval, duration);
            tune.tuneBelowCapacity = core_.capacity - tune.tuneIntervalCapacity;
            // TODO should we enforce a maximum tune gain? there is likely a level above which it will greatly misbehave
            tune.tuneGain = tuneGain;
        }
    }

    /* ========== TELLER FUNCTIONS ========== */

    function __purchase(uint256 id_, uint256 amount_) internal override returns (uint256) {
        // If tuning, apply any active adjustments to the equilibrium price
        if (auctionData[id_].tuning) {
            // The market equilibrium price can optionally be tuned to keep the market on schedule.
            // When it is lowered, the change is carried out smoothly over the tuneAdjustmentDelay.
            Adjustment storage adjustment = adjustments[id_];
            if (adjustment.active) {
                // Update equilibrium price with adjusted price
                auctionData[id_].equilibriumPrice = _adjustedEquilibriumPrice(
                    auctionData[id_].equilibriumPrice,
                    adjustment
                );

                // Update adjustment data
                if (stillActive) {
                    adjustment.change -= adjustBy;
                    adjustment.timeToAdjusted -= secondsSince;
                    adjustment.lastAdjustment = time_;
                } else {
                    adjustment.active = false;
                }
            }
        }

        // Calculate payout
        uint256 price = marketPrice(id_);
        uint256 payout = amount_.mulDiv(styleData[id_].scale, price);

        // If tuning, attempt to tune the market
        // The payout value is required and capacity isn't updated until we provide this data back to the top level function.
        // Therefore, the function manually handles updates to capacity when tuning.
        if (auction.tuning) _tune(id_, price);

        return payout;
    }

    function _tune(uint256 id_, uint256 price_, uint256 amount_, uint256 payout_) internal {
        CoreData memory core = coreData[id_];
        StyleData memory style = styleData[id_];
        AuctionData memory auction = auctionData[id_];
        TuneData storage tune = tuneData[id_];

        // Market tunes in 2 situations:
        // 1. If capacity has exceeded target since last tune adjustment and the market is oversold
        // 2. If a tune interval has passed since last tune adjustment and the market is undersold
        //
        // Markets are created with a target capacity with the expectation that capacity will
        // be utilized evenly over the duration of the market.
        // The intuition with tuning is:
        // - When the market is ahead of target capacity, we should tune based on capacity.
        // - When the market is behind target capacity, we should tune based on time.
        //
        // Tuning is equivalent to using a P controller to adjust the price to stay on schedule with selling capacity.
        // We don't want to make adjustments when the market is close to on schedule to avoid overcorrections.
        // Adjustments should undershoot rather than overshoot the target.

        // Compute seconds remaining until market will conclude and total duration of market
        uint256 currentTime = block.timestamp;
        uint256 timeRemaining = uint256(core.conclusion - currentTime);
        uint256 duration = uint256(core.conclusion - core.start);

        // Subtract amount / payout for this purchase from capacity since it hasn't been updated in the state yet.
        // If it is greater than capacity, revert.
        if (core.capacityInQuote ? amount_ > capacity : payout_ > capacity)
            revert Auctioneer_InsufficientCapacity();
        uint256 capacity = capacityInQuote ? core.capacity - amount_ : core.capacity - payout_;

        // Calculate initial capacity based on remaining capacity and amount sold/purchased up to this point
        uint256 initialCapacity = capacity +
            (core.capacityInQuote ? core.purchased + amount_ : core.sold + payout_);

        // Calculate expectedCapacity as the capacity expected to be bought or sold up to this point
        // Higher than current capacity means the market is undersold, lower than current capacity means the market is oversold
        uint256 expectedCapacity = initialCapacity.mulDiv(timeRemaining, duration);

        if (
            (capacity < tune.tuneBelowCapacity && capacity < expectedCapacity) ||
            (currentTime >= tune.lastTune + tune.tuneInterval && capacity > expectedCapacity)
        ) {
            // Calculate and apply tune adjustment

            // Calculate the percent delta expected and current capacity
            uint256 delta = capacity > expectedCapacity
                ? ((capacity - expectedCapacity) * ONE_HUNDRED_PERCENT) / initialCapacity
                : ((expectedCapacity - capacity) * ONE_HUNDRED_PERCENT) / initialCapacity;

            // Do not tune if the delta is within a reasonable range based on the deposit interval
            // Market capacity does not decrease continuously, but follows a step function
            // based on purchases. If the capacity deviation is less than the amount of capacity in a
            // deposit interval, then we should not tune.
            if (delta < (style.depositInterval * ONE_HUNDRED_PERCENT) / duration) return;

            // Apply the controller gain to the delta to determine the amount of change
            delta = (delta * tune.gain) / ONE_HUNDRED_PERCENT;
            if (capacity > expectedCapacity) {
                // Apply a tune adjustment since the market is undersold

                // Create an adjustment to lower the equilibrium price by delta percent over the tune adjustment delay
                Adjustment storage adjustment = adjustments[id_];
                adjustment.active = true;
                adjustment.change = auction.equilibriumPrice.mulDiv(delta, ONE_HUNDRED_PERCENT);
                adjustment.lastAdjustment = currentTime;
                adjustment.timeToAdjusted = tune.tuneAdjustmentDelay;
            } else {
                // Immediately tune up since the market is oversold

                // Increase equilibrium price by delta percent
                auctionData[id_].equilibriumPrice = auction.equilibriumPrice.mulDiv(
                    ONE_HUNDRED_PERCENT + delta,
                    ONE_HUNDRED_PERCENT
                );

                // Set current adjustment to inactive (e.g. if we are re-tuning early)
                adjustment.active = false;
            }

            // Update tune data
            tune.lastTune = currentTime;
            tune.tuneBelowCapacity = capacity > tune.tuneIntervalCapacity
                ? capacity - tune.tuneIntervalCapacity
                : 0;

            // Calculate the correct payout to complete on time assuming each bond
            // will be max size in the desired deposit interval for the remaining time
            //
            // i.e. market has 10 days remaining. deposit interval is 1 day. capacity
            // is 10,000 TOKEN. max payout would be 1,000 TOKEN (10,000 * 1 / 10).
            uint256 payoutCapacity = core.capacityInQuote
                ? capacity.mulDiv(style.scale, price_)
                : capacity;
            styleData[id_].maxPayout = payoutCapacity.mulDiv(
                uint256(style.depositInterval),
                timeRemaining
            );

            emit Tuned(id_);
        }
    }

    /* ========== ADMIN FUNCTIONS ========== */
    /* ========== VIEW FUNCTIONS ========== */

    function _adjustedEquilibriumPrice(
        uint256 equilibriumPrice_,
        Adjustment memory adjustment_
    ) internal view returns (uint256) {
        // Adjustment should be active if passed to this function.
        // Calculate the change to apply based on the time elapsed since the last adjustment.
        uint256 timeElapsed = block.timestamp - adjustment_.lastAdjustment;

        // If timeElapsed is zero, return early since the adjustment has already been applied up to the present.
        if (timeElapsed == 0) return equilibriumPrice_;

        uint256 timeToAdjusted = adjustment_.timeToAdjusted;
        bool stillActive = timeElapsed < timeToAdjusted;
        uint256 change = stillActive
            ? adjustment_.change.mulDiv(timeElapsed, timeToAdjusted)
            : adjustment_.change;
        return equilibriumPrice_ - change;
    }

    /// @inheritdoc ISequentialDutchAuctioneer
    function marketPrice(uint256 id_) public view override returns (uint256) {
        CoreData memory core = coreData[id_];
        AuctionData memory auction = auctionData[id_];

        // Calculate initial capacity based on remaining capacity and amount sold/purchased up to this point
        uint256 initialCapacity = core.capacity +
            (core.capacityInQuote ? core.purchased : core.sold);

        // Compute seconds remaining until market will conclude
        uint256 timeRemaining = core.conclusion - block.timestamp;

        // Calculate expectedCapacity as the capacity expected to be bought or sold up to this point
        // Higher than current capacity means the market is undersold, lower than current capacity means the market is oversold
        uint256 expectedCapacity = initialCapacity.mulDiv(
            timeRemaining,
            uint256(core.conclusion) - uint256(core.start)
        );

        // If tuning, apply any active adjustments to the equilibrium price before decaying
        uint256 price = auction.equilibriumPrice;
        if (auction.tuning) {
            Adjustment memory adjustment = adjustments[id_];
            if (adjustment.active) price = _adjustedEquilibriumPrice(price, adjustment);
        }

        // Price is increased or decreased based on how far the market is ahead or behind
        // Intuition:
        // If the time neutral capacity is higher than the initial capacity, then the market is undersold and price should be discounted
        // If the time neutral capacity is lower than the initial capacity, then the market is oversold and price should be increased
        //
        // This implementation uses a linear price decay
        // P(t) = P_eq * (1 + k * (X(t) - C(t) / C(0)))
        // P(t): price at time t
        // P_eq: equilibrium price of the market, initialized by issuer on market creation and potential updated via tuning
        // k: decay speed of the market
        // k = L / I * d, where L is the duration/length of the market, I is the deposit interval, and d is the target interval discount.
        // X(t): expected capacity of the market at time t.
        // X(t) = C(0) * t / L.
        // C(t): actual capacity of the market at time t.
        // C(0): initial capacity of the market provided by the user (see IOSDA.MarketParams).
        uint256 decay;
        if (expectedCapacity > core.capacity) {
            decay =
                ONE_HUNDRED_PERCENT +
                (auction.decaySpeed * (expectedCapacity - core.capacity)) /
                initialCapacity;
        } else {
            // If actual capacity is greater than expected capacity, we need to check for underflows
            // The decay has a minimum value of 0 since that will reduce the price to 0 as well.
            uint256 factor = (auction.decaySpeed * (core.capacity - expectedCapacity)) /
                initialCapacity;
            decay = ONE_HUNDRED_PERCENT > factor ? ONE_HUNDRED_PERCENT - factor : 0;
        }

        // Apply decay to price (could be negative decay - i.e. a premium to the equilibrium)
        price = price.mulDivUp(decay, ONE_HUNDRED_PERCENT);

        // Compare the current price to the minimum price and return the maximum
        return price > auction.minPrice ? price : auction.minPrice;
    }
}
