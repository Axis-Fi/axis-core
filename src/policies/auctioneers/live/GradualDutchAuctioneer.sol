/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Auctioneer, IAggregator, Authority} from "src/auctioneers/bases/Auctioneer.sol";
import {IGradualDutchAuctioneer} from "src/interfaces/IGradualDutchAuctioneer.sol";
import {SD59x18, sd, convert, uUNIT} from "prb-math/SD59x18.sol";

contract GradualDutchAuctioneer is Auctioneer, IGradualDutchAuctioneer {
    /* ========== ERRORS ========== */
    /* ========== STATE ========== */

    SD59x18 public constant ONE = convert(int256(1));

    mapping(uint256 id => AuctionData data) public auctionData;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IAggregator aggregator_,
        address guardian_,
        Authority authority_
    ) Auctioneer(aggregator_, guardian_, authority_) {}

    /* ========== MARKET FUNCTIONS ========== */

    function _createMarket(
        uint256 id_,
        CoreData memory core_,
        bytes memory params_
    ) internal override {
        // Decode params
    }

    /* ========== TELLER FUNCTIONS ========== */

    function _purchase(uint256 id_, uint256 amount_) internal override returns (uint256) {
        // Calculate payout amount for quote amount and seconds of emissions using GDA formula
        (uint256 payout, uint48 secondsOfEmissions) = _payoutAndEmissionsFor(id_, amount_);

        // Update last auction start with seconds of emissions
        // Do not have to check that too many seconds have passed here
        // since payout/amount is checked against capacity in the top-level function
        auctionData[id_].lastAuctionStart += secondsOfEmissions;

        return payout;
    }

    /* ========== PRICE FUNCTIONS ========== */

    function marketPriceFor(uint256 id_, uint256 payout_) external view returns (uint256) {
        Decay decayType = auctionData[id_].decayType;

        uint256 amount;
        if (decayType == Decay.EXPONENTIAL) {
            amount = _exponentialPriceFor(id_, payout_);
        } else if (decayType == Decay.LINEAR) {
            amount = _linearPriceFor(id_, payout_);
        }

        // Check that amount in or payout do not exceed remaining capacity
        CoreData memory core = coreData[id_];
        if (core.capacityInQuote ? amount > core.capacity : payout_ > core.capacity)
            revert Auctioneer_InsufficientCapacity();
    }

    // For Continuos GDAs with exponential decay, the price of a given token t seconds after being emitted is: p(t) = p0 * e^(-k*t)
    // Integrating this function from the last auction start time for a particular number of tokens, gives the multiplier for the token price to determine amount of quote tokens required to purchase
    // P(T) = (p0 / k) * (e^(k*q) - 1) / e^(k*T) where T is the time since the last auction start, q is the number of tokens to purchase, and p0 is the initial price
    function _exponentialPriceFor(uint256 id_, uint256 payout_) internal view returns (uint256) {
        CoreData memory core = coreData[id_];
        AuctionData memory auction = auctionData[id_];

        // Convert payout to SD59x18. We scale first to 18 decimals from the payout token decimals
        uint256 payoutTokenScale = 10 ** (core.payoutToken.decimals());
        SD59x18 payout = sd(int256(payout_.mulDiv(uUNIT, payoutTokenScale)));

        // Calculate time since last auction start
        SD59x18 timeSinceLastAuctionStart = convert(
            int256(block.timestamp - uint256(auction.lastAuctionStart))
        );

        // Calculate the first numerator factor
        SD59x18 num1 = sd(int256(auction.equilibriumPrice.mulDiv(uUNIT, auction.scale))).div(
            auction.decayConstant
        );

        // Calculate the second numerator factor
        SD59x18 num2 = auction.decayConstant.mul(payout).exp().sub(ONE);

        // Calculate the denominator
        SD59x18 denominator = auction.decayConstant.mul(timeSinceLastAuctionStart).exp();

        // Calculate return value
        // This value should always be positive, therefore, we can safely cast to uint256
        // We scale the return value back to payout token decimals
        return num1.mul(num2).div(denominator).intoUint256().mulDiv(payoutTokenScale, uUNIT);
    }

    // p(t) = p0 * (1 - k*t) where p0 is the initial price, k is the decay constant, and t is the time since the last auction start
    // P(T) = (p0 * q / r) * (1 - k*T + k*q/2r) where T is the time since the last auction start, q is the number of tokens to purchase,
    // r is the emissions rate, and p0 is the initial price
    function _linearPriceFor(uint256 id_, uint256 payout_) internal view returns (uint256) {
        CoreData memory core = coreData[id_];
        AuctionData memory auction = auctionData[id_];

        // Convert payout to SD59x18. We scale first to 18 decimals from the payout token decimals
        uint256 payoutTokenScale = 10 ** (core.payoutToken.decimals());
        SD59x18 payout = sd(int256(payout_.mulDiv(uUNIT, payoutTokenScale)));

        // Calculate time since last auction start
        SD59x18 timeSinceLastAuctionStart = convert(
            int256(block.timestamp - uint256(auction.lastAuctionStart))
        );

        // Calculate decay factor
        // TODO can we confirm this will be positive?
        SD59x18 decayFactor = ONE.sub(auction.decayConstant.mul(timeSinceLastAuctionStart)).add(
            auction.decayConstant.mul(payout).div(convert(int256(2)).mul(auction.emissionsRate))
        );

        // Calculate payout factor
        SD59x18 payoutFactor = payout.mul(
            sd(int256(auction.equilibriumPrice.mulDiv(uUNIT, auction.scale)))
        );

        // Calculate final return value and convert back to market scale
        return
            payoutFactor.mul(decayFactor).div(auction.emissionsRate).intoUint256().mulDiv(
                auction.scale,
                uUNIT
            );
    }

    /* ========== PAYOUT CALCULATIONS ========== */

    function _payoutFor(uint256 id_, uint256 amount_) internal view override returns (uint256) {
        CoreData memory core = coreData[id_];

        (uint256 payout, ) = _payoutAndEmissionsFor(id_, amount_);

        // Check that amount in or payout do not exceed remaining capacity
        if (core.capacityInQuote ? amount_ > core.capacity : payout > core.capacity)
            revert Auctioneer_InsufficientCapacity();

        return payout;
    }

    function _payoutAndEmissionsFor(
        uint256 id_,
        uint256 amount_
    ) internal view returns (uint256, uint48) {
        Decay decayType = auctionData[id_].decayType;

        if (decayType == Decay.EXPONENTIAL) {
            return _payoutForExpDecay(id_, amount_);
        } else if (decayType == Decay.LINEAR) {
            return _payoutForLinearDecay(id_, amount_);
        } else {
            revert Auctioneer_InvalidParams();
        }
    }

    // P = (r / k) * ln(Q * k / p0 * e^(k*T) + 1) where P is the number of payout tokens, Q is the number of quote tokens, r is the emissions rate, k is the decay constant,
    // p0 is the price target of the market, and T is the time since the last auction start
    function _payoutForExpDecay(
        uint256 id_,
        uint256 amount_
    ) internal view returns (uint256, uint48) {
        CoreData memory core = coreData[id_];
        AuctionData memory auction = auctionData[id_];

        // Convert to 18 decimals for fixed math by pre-computing the Q / p0 factor (which is in payout token units)
        // and then scaling using payout token decimals
        uint256 payoutTokenScale = 10 ** uint256(core.payoutToken.decimals());
        SD59x18 scaledQ = sd(
            int256(
                amount_.mulDiv(auction.scale, auction.targetPrice).mulDiv(uUNIT, payoutTokenScale)
            )
        );

        // Calculate time since last auction start
        SD59x18 timeSinceLastAuctionStart = convert(
            int256(block.timestamp - uint256(auction.lastAuctionStart))
        );

        // Calculate the logarithm
        SD59x18 logFactor = auction
            .decayConstant
            .mul(timeSinceLastAuctionStart)
            .exp()
            .mul(scaledQ)
            .mul(auction.decayConstant)
            .add(ONE)
            .ln();

        // Calculate the payout
        SD59x18 payout = logFactor.mul(auction.emissionsRate).div(auction.decayConstant);

        // Scale back to payout token decimals
        // This value should always be positive since it is atleast 1, therefore, we can safely cast to uint256
        return payout.intoUint256().mulDiv(payoutTokenScale, uUNIT);

        // Calculate seconds of emissions from payout or amount (depending on capacity type)
        uint48 secondsOfEmissions;
        if (core.capacityInQuote) {
            // Convert amount to SD59x18
            SD59x18 amount = sd(int256(amount_.mulDiv(uUNIT, auction.scale)));
            secondsOfEmissions = uint48(amount.div(auction.emissionsRate).intoUint256());
        } else {
            secondsOfEmissions = uint48(payout.div(auction.emissionsRate).intoUint256());
        }

        // Scale payout to payout token decimals and return
        // Payout should always be positive since it is atleast 1, therefore, we can safely cast to uint256
        return (payout.intoUint256().mulDiv(payoutTokenScale, uUNIT), secondsOfEmissions);
    }

    // P = (r / k) * (sqrt(2 * k * Q / p0) + k * T - 1) where P is the number of payout tokens, Q is the number of quote tokens, r is the emissions rate, k is the decay constant,
    // p0 is the price target of the market, and T is the time since the last auction start
    function _payoutForLinearDecay(uint256 id_, uint256 amount_) internal view returns (uint256) {
        CoreData memory core = coreData[id_];
        AuctionData memory auction = auctionData[id_];

        // Convert to 18 decimals for fixed math by pre-computing the Q / p0 factor (which is in payout token units)
        // and then scaling using payout token decimals
        uint256 payoutTokenScale = uint256(core.payoutToken.decimals());
        SD59x18 scaledQ = sd(
            int256(amount_.mulDiv(auction.scale, auction.price).mulDiv(uUNIT, payoutTokenScale))
        );

        // Calculate time since last auction start
        SD59x18 timeSinceLastAuctionStart = convert(
            int256(block.timestamp - uint256(auction.lastAuctionStart))
        );

        // Calculate factors
        SD59x18 sqrtFactor = convert(int256(2)).mul(auction.decayConstant).mul(scaledQ).sqrt();
        SD59x18 factor = sqrtFactor.add(auction.decayConstant.mul(timeSinceLastAuctionStart)).sub(
            ONE
        );

        // Calculate payout
        SD59x18 payout = auction.emissionsRate.div(auction.decayConstant).mul(factor);

        // Calculate seconds of emissions from payout or amount (depending on capacity type)
        uint48 secondsOfEmissions;
        if (core.capacityInQuote) {
            // Convert amount to SD59x18
            SD59x18 amount = sd(int256(amount_.mulDiv(uUNIT, auction.scale)));
            secondsOfEmissions = uint48(amount.div(auction.emissionsRate).intoUint256());
        } else {
            secondsOfEmissions = uint48(payout.div(auction.emissionsRate).intoUint256());
        }

        // Scale payout to payout token decimals and return
        return (payout.intoUint256().mulDiv(payoutTokenScale, uUNIT), secondsOfEmissions);
    }
    /* ========== ADMIN FUNCTIONS ========== */
    /* ========== VIEW FUNCTIONS ========== */
}
