// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {IAuctioneer} from "src/interfaces/IAuctioneer.sol";

interface IMaxPayoutAuctioneer {
    struct StyleData {
        uint48 depositInterval; // target interval between deposits
        uint256 maxPayout; // maximum payout for a single purchase
        uint256 scale; // stored scale for market price
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice Set the minimum deposit interval
    /// @notice Access controlled
    /// @param depositInterval_ Minimum deposit interval in seconds
    function setMinDepositInterval(uint48 depositInterval_) external;

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice             Calculate current market price of payout token in quote tokens
    /// @param id_          ID of market
    /// @return             Price for market in configured decimals
    function marketPrice(uint256 id_) external view returns (uint256);

    /// @notice             Scale value to use when converting between quote token and payout token amounts with marketPrice()
    /// @param id_          ID of market
    /// @return             Scaling factor for market in configured decimals
    function marketScale(uint256 id_) external view returns (uint256);

    /// @notice             Calculate max payout of the market in payout tokens
    /// @dev                Returns a dynamically calculated payout or the maximum set by the creator, whichever is less.
    /// @param id_          ID of market
    /// @return             Current max payout for the market in payout tokens
    function maxPayout(uint256 id_) external view returns (uint256);
}
