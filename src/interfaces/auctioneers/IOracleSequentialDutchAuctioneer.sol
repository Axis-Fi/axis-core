// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {IMaxPayoutAuctioneer} from "src/interfaces/IMaxPayoutAuctioneer.sol";

interface IOracleSequentialDutchAuctioneer is IMaxPayoutAuctioneer {
    /// @notice Auction pricing data
    struct AuctionData {
        IBondOracle oracle; // oracle to use for equilibrium price
        uint48 baseDiscount; // base discount from the oracle price to be used to determine equilibrium price
        bool conversionMul; // whether to multiply (true) or divide (false) oracle price by conversion factor
        uint256 conversionFactor; // conversion factor for oracle price to market price scale
        uint256 minPrice; // minimum price for the auction
        uint48 decaySpeed; // market price decay speed (discount achieved over a target deposit interval)
        bool tuning; // whether or not the auction tunes the equilibrium price
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice             Calculate current market price of payout token in quote tokens
    /// @param id_          ID of market
    /// @return             Price for market in configured decimals (see MarketParams)
    /// @dev price is derived from the equation
    //
    // p(t) = max(min_p, p_o * (1 - d) * (1 + k * r(t)))
    //
    // where
    // p: price
    // min_p: minimum price
    // p_o: oracle price
    // d: base discount
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
