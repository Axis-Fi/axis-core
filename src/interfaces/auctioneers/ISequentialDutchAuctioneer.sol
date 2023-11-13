// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

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
