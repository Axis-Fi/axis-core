// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {IMaxPayoutAuctioneer} from "src/interfaces/IMaxPayoutAuctioneer.sol";

interface IFixedPriceAuctioneer is IMaxPayoutAuctioneer {
    /// @notice             Calculate current market price of payout token in quote tokens
    /// @param id_          ID of market
    /// @return             Price for market in configured decimals (see MarketParams)
    /// @dev price is derived from the equation:
    //
    // p = f_p
    //
    // where
    // p = price
    // f_p = fixed price provided on creation
    //
    function marketPrice(uint256 id_) external view override returns (uint256);
}
