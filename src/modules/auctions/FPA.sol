/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {MaxPayoutAuctioneer, IAggregator, Authority} from "src/auctioneers/bases/MaxPayoutAuctioneer.sol";

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


contract FixedPriceAuctioneer is MaxPayoutAuctioneer, IFixedPriceAuctioneer {
    /* ========== STATE ========== */

    mapping(uint256 id => uint256 price) internal fixedPrices;

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
        uint256 fixedPrice = abi.decode(params_, (uint256));

        // Validate that fixed price is not zero
        if (fixedPrice == 0) revert Auctioneer_InvalidParams();

        // Set fixed price
        fixedPrices[id_] = fixedPrice;
    }

    /* ========== TELLER FUNCTIONS ========== */

    function __purchase(uint256 id_, uint256 amount_) internal override returns (uint256) {
        // Calculate the payout from the fixed price and return
        return amount_.mulDiv(styleData[id_].scale, marketPrice(id_));
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc IFixedPriceAuctioneer
    function marketPrice(uint256 id_) public view override returns (uint256) {
        return fixedPrices[id_];
    }
}
