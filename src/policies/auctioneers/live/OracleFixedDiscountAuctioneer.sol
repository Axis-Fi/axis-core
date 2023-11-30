/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {MaxPayoutAuctioneer, IAggregator, Authority} from "src/auctioneers/bases/MaxPayoutAuctioneer.sol";
import {IFixedPriceAuctioneer} from "src/interfaces/IFixedPriceAuctioneer.sol";
import {OracleHelper} from "src/lib/OracleHelper.sol";

contract OracleFixedDiscountAuctioneer is MaxPayoutAuctioneer, IOracleFixedDiscountAuctioneer {
    /* ========== ERRORS ========== */
    error Auctioneer_OraclePriceZero();

    /* ========== STATE ========== */

    mapping(uint256 id => AuctionData) internal auctionData;

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
        // Decode params
        (IBondOracle oracle, uint48 fixedDiscount, uint48 maxDiscountFromCurrent) = abi.decode(
            params_,
            (IBondOracle, uint48, uint48)
        );

        // Validate oracle
        (uint256 oraclePrice, uint256 conversionFactor, bool conversionMul) = OracleHelper
            .validateOracle(id_, oracle, core_.quoteToken, core_.payoutToken, fixedDiscount);

        // Validate discounts
        if (
            fixedDiscount >= ONE_HUNDRED_PERCENT ||
            maxDiscountFromCurrent > ONE_HUNDRED_PERCENT ||
            fixedDiscount > maxDiscountFromCurrent
        ) revert Auctioneer_InvalidParams();

        // Set auction data
        AuctionData storage auction = auctionData[id_];
        auction.oracle = oracle;
        auction.fixedDiscount = fixedDiscount;
        auction.conversionMul = conversionMul;
        auction.conversionFactor = conversionFactor;
        auction.minPrice = oraclePrice.mulDivUp(
            ONE_HUNDRED_PERCENT - maxDiscountFromCurrent,
            ONE_HUNDRED_PERCENT
        );
    }

    /* ========== TELLER FUNCTIONS ========== */

    function __purchase(uint256 id_, uint256 amount_) internal override returns (uint256) {
        // Calculate the payout from the market price and return
        return amount_.mulDiv(styleData[id_].scale, marketPrice(id_));
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc IOracleFixedDiscountAuctioneer
    function marketPrice(uint256 id_) public view override returns (uint256) {
        // Get auction data
        AuctionData memory auction = auctionData[id_];

        // Get oracle price
        uint256 oraclePrice = auction.oracle.currentPrice(id_);

        // Revert if oracle price is 0
        if (oraclePrice == 0) revert Auctioneer_OraclePriceZero();

        // Apply conversion factor
        if (auction.conversionMul) {
            oraclePrice *= auction.conversionFactor;
        } else {
            oraclePrice /= auction.conversionFactor;
        }

        // Apply fixed discount
        uint256 price = oraclePrice.mulDivUp(
            uint256(ONE_HUNDRED_PERCENT - auction.fixedDiscount),
            uint256(ONE_HUNDRED_PERCENT)
        );

        // Compare the current price to the minimum price and return the maximum
        return price > auction.minPrice ? price : auction.minPrice;
    }
}
