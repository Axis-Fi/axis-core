// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {IMaxPayoutAuctioneer} from "src/interfaces/IMaxPayoutAuctioneer.sol";

interface IOracleFixedDiscountAuctioneer is IMaxPayoutAuctioneer {
    /// @notice Auction pricing data
    struct AuctionData {
        IBondOracle oracle;
        uint48 fixedDiscount;
        bool conversionMul;
        uint256 conversionFactor;
        uint256 minPrice;
    }

    /// @notice             Calculate current market price of payout token in quote tokens
    /// @param id_          ID of market
    /// @return             Price for market in configured decimals (see MarketParams)
    /// @dev price is derived from the equation:
    //
    // p = max(min_p, o_p * (1 - d))
    //
    // where
    // p = price
    // min_p = minimum price
    // o_p = oracle price
    // d = fixed discount
    //
    // if price is below minimum price, minimum price is returned
    function marketPrice(uint256 id_) external view returns (uint256);
}
