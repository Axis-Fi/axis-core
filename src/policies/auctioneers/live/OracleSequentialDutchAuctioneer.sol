/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {MaxPayoutAuctioneer, IAggregator, Authority} from "src/auctioneers/bases/MaxPayoutAuctioneer.sol";
import {IFixedPriceAuctioneer} from "src/interfaces/IFixedPriceAuctioneer.sol";
import {OracleHelper} from "src/lib/OracleHelper.sol";

contract OracleSequentialDutchAuctioneer is MaxPayoutAuctioneer, IOracleSequentialDutchAuctioneer {
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
        (
            IBondOracle oracle,
            uint48 baseDiscount,
            uint48 maxDiscountFromCurrent,
            uint48 targetIntervalDiscount
        ) = abi.decode(params_, (IBondOracle, uint48, uint48));

        // Validate oracle
        (uint256 oraclePrice, uint256 conversionFactor, bool conversionMul) = OracleHelper
            .validateOracle(id_, oracle, core_.quoteToken, core_.payoutToken, fixedDiscount);

        // Validate discounts
        if (
            baseDiscount >= ONE_HUNDRED_PERCENT ||
            maxDiscountFromCurrent > ONE_HUNDRED_PERCENT ||
            baseDiscount > maxDiscountFromCurrent
        ) revert Auctioneer_InvalidParams();

        // Set auction data
        AuctionData storage auction = auctionData[id_];
        auction.oracle = oracle;
        auction.baseDiscount = baseDiscount;
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

    /// @inheritdoc IOracleSequentialDutchAuctioneer
    function marketPrice(uint256 id_) public view override returns (uint256) {
        // Get auction data
        AuctionData memory auction = auctionData[id_];

        // Get oracle price
        uint256 price = auction.oracle.currentPrice(id_);

        // Revert if oracle price is 0
        if (price == 0) revert Auctioneer_OraclePriceZero();

        // Apply conversion factor
        if (auction.conversionMul) {
            price *= auction.conversionFactor;
        } else {
            price /= auction.conversionFactor;
        }

        // Apply base discount
        price = price.mulDivUp(
            uint256(ONE_HUNDRED_PERCENT - auction.baseDiscount),
            uint256(ONE_HUNDRED_PERCENT)
        );

        // Calculate initial capacity based on remaining capacity and amount sold/purchased up to this point
        uint256 initialCapacity = market.capacity +
            (market.capacityInQuote ? market.purchased : market.sold);

        // Compute seconds remaining until market will conclude
        uint256 conclusion = uint256(term.conclusion);
        uint256 timeRemaining = conclusion - block.timestamp;

        // Calculate expectedCapacity as the capacity expected to be bought or sold up to this point
        // Higher than current capacity means the market is undersold, lower than current capacity means the market is oversold
        uint256 expectedCapacity = initialCapacity.mulDiv(
            timeRemaining,
            conclusion - uint256(term.start)
        );

        // Price is increased or decreased based on how far the market is ahead or behind
        // Intuition:
        // If the time neutral capacity is higher than the initial capacity, then the market is undersold and price should be discounted
        // If the time neutral capacity is lower than the initial capacity, then the market is oversold and price should be increased
        //
        // This implementation uses a linear price decay
        // P(t) = P(0) * (1 + k * (X(t) - C(t) / C(0)))
        // P(t): price at time t
        // P(0): target price of the market provided by oracle + base discount (see IOSDA.MarketParams)
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
