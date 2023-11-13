/// SPDX-License-Identifer: AGPL-3.0
pragma solidity 0.8.19;

import "src/modules/HOUSE/HOUSE.v1.sol";

contract SequentialDutchAuction is AuctionSubmodule {

    // ========== STATE VARIABLES ========== //
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

}