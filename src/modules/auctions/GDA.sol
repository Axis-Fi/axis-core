// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Protocol dependencies
import {Module} from "src/modules/Modules.sol";
import {AuctionModule} from "src/modules/Auction.sol";
import {Veecode, toVeecode} from "src/modules/Modules.sol";
import {AtomicAuctionModule} from "src/modules/auctions/AtomicAuctionModule.sol";

// External libraries
import {UD60x18, ud, convert, ZERO, UNIT, uUNIT} from "lib/prb-math/src/UD60x18.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";

/// @notice Continuous Gradual Dutch Auction (GDA) module with exponential decay and a minimum price.
contract GradualDutchAuction is AtomicAuctionModule {
    using FixedPointMathLib for uint256;

    /// @notice Auction pricing data
    struct AuctionData {
        uint256 equilibriumPrice; // price at which the auction is balanced
        uint256 minimumPrice; // minimum price for the auction
        uint256 lastAuctionStart; // time that the last un-purchased auction started, may be in the future
        UD60x18 decayConstant; // speed at which the price decays, as UD60x18.
        UD60x18 emissionsRate; // number of tokens released per second, as UD60x18. Calculated as capacity / duration.
    }

    struct GDAParams {
        uint256 equilibriumPrice;
        uint256 minimumPrice;
        uint256 decayPercentFirstPeriod; // target decay percent over the first decay period of an auction (steepest part of the curve)
        uint256 decayPeriod; // period over which the target decay percent is reached
    }

    // ========== STATE VARIABLES ========== //

    // Decay percent over the first period must be at most 99% and at least 1%
    // We use 18 decimals so we don't have to convert it to use as a UD60x18
    uint256 internal constant MIN_DECAY_PERCENT = 1e16; // 1%
    uint256 internal constant MAX_DECAY_PERCENT = 99e16; // 99%

    // Decay period must be greater than or equal to 1 hour and less than or equal to 1 week
    // A minimum of 1 hour means that the maximum value for the decay constant is determined by:
    // MAX_LN_OUTPUT = 135_999146549453176925
    // MAX_LN_OUTPUT / 3600 = 0_037777540708181438
    // A maximum of 1 week means that the minimum value for the decay constant is determined by:
    // MIN_LN_OUTPUT = ln(1/0.99) = 0_010050335853501441
    // MIN_LN_OUTPUT / 604800 = 0_000000016617618805
    // We use these bounds to prove that various calculations won't overflow below
    // TODO: implement the above
    // TODO should we be able to update the min and max periods?
    uint48 internal constant MIN_DECAY_PERIOD = 1 hours;
    uint48 internal constant MAX_DECAY_PERIOD = 1 weeks;
    UD60x18 internal constant MAX_DECAY_CONSTANT = UD60x18.wrap(uint256(37_777_540_708_181_438));
    UD60x18 internal constant MIN_DECAY_CONSTANT = UD60x18.wrap(uint256(16_617_618_805));

    mapping(uint256 id => AuctionData data) public auctionData;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // TODO think about appropriate minimum for auction duration
        minAuctionDuration = 1 days;
    }

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01GDA");
    }

    // ========== AUCTION ========== //

    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override {
        // Decode implementation parameters
        GDAParams memory params = abi.decode(params_, (GDAParams));

        // Validate parameters
        // Equilibrium Price must not be zero and greater than minimum price (which can be zero)
        if (params.equilibriumPrice == 0 || params.equilibriumPrice <= params.minimumPrice) {
            revert Auction_InvalidParams();
        }

        // Capacity must be in base token
        if (lot_.capacityInQuote) revert Auction_InvalidParams();

        // Minimum price can be zero, but the equations default back to the basic GDA implementation

        // Validate the decay parameters and calculate the decay constant
        // k = ln((q0 - qm) / (q1 - qm)) / dp
        // require q0 > q1 > qm
        // q1 = q0 * (1 - d1)
        // => 100% > d1 > 0%
        if (params.decayPercentFirstPeriod >= uUNIT || params.decayPercentFirstPeriod < uUNIT / 100)
        {
            revert Auction_InvalidParams();
        }

        // Decay period must be between the set bounds
        if (params.decayPeriod < MIN_DECAY_PERIOD || params.decayPeriod > MAX_DECAY_PERIOD) {
            revert Auction_InvalidParams();
        }

        UD60x18 decayConstant;
        {
            uint256 quoteTokenScale = 10 ** lot_.quoteTokenDecimals;
            UD60x18 q0 = ud(params.equilibriumPrice.fullMulDiv(uUNIT, quoteTokenScale));
            UD60x18 q1 = q0.mul(UNIT - ud(params.decayPercentFirstPeriod)).div(UNIT);
            UD60x18 qm = ud(params.minimumPrice.fullMulDiv(uUNIT, quoteTokenScale));

            // Check that q0 > q1 > qm
            // This ensures that the operand for the logarithm is positive
            if (q0 <= q1 || q1 <= qm) {
                revert Auction_InvalidParams();
            }

            // Calculate the decay constant
            decayConstant = (q0 - qm).div(q1 - qm).ln().div(convert(params.decayPeriod));
        }

        // TODO other validation checks?

        // Calculate emissions rate
        UD60x18 duration = convert(uint256(lot_.conclusion - lot_.start));
        UD60x18 emissionsRate =
            ud(lot_.capacity.fullMulDiv(uUNIT, 10 ** lot_.baseTokenDecimals)).div(duration);

        // Store auction data
        AuctionData storage data = auctionData[lotId_];
        data.equilibriumPrice = params.equilibriumPrice;
        data.minimumPrice = params.minimumPrice;
        data.decayConstant = decayConstant;
        data.emissionsRate = emissionsRate;
        data.lastAuctionStart = uint256(lot_.start);
    }

    // Do not need to do anything extra here
    function _cancelAuction(uint96 lotId_) internal override {}

    // ========== PURCHASE ========== //

    function _purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata
    ) internal override returns (uint256 payout, bytes memory auctionOutput) {
        // Calculate the payout and emissions
        uint256 secondsOfEmissions;
        (payout, secondsOfEmissions) = _payoutAndEmissionsFor(lotId_, amount_);

        // Update last auction start with seconds of emissions
        // Do not have to check that too many seconds have passed here
        // since payout is checked against capacity in the top-level function
        auctionData[lotId_].lastAuctionStart += secondsOfEmissions;

        // Return the payout and emissions
        return (payout, bytes(""));
    }

    // ========== VIEW FUNCTIONS ========== //

    // For Continuos GDAs with exponential decay, the price of a given token t seconds after being emitted is:
    // q(t) = (q0 - qm) * e^(-k*t) + qm
    // where k is the decay constant, q0 is the initial price, and qm is the minimum price
    // Integrating this function from the last auction start time for a particular number of tokens,
    // gives the multiplier for the token price to determine amount of quote tokens required to purchase:
    // Q(T) = ((q0 - qm) * (e^((k*P)/r) - 1)) / ke^(k*T) + (qm * P) / r
    // where T is the time since the last auction start, P is the number of payout tokens to purchase,
    // and r is the emissions rate (number of tokens released per second).
    //
    // If qm is 0, then the equation simplifies to:
    // q(t) = q0 * e^(-k*t)
    // Integrating this function from the last auction start time for a particular number of tokens,
    // gives the multiplier for the token price to determine amount of quote tokens required to purchase:
    // Q(T) = (q0 * (e^((k*P)/r) - 1)) / ke^(k*T)
    // where T is the time since the last auction start, P is the number of payout tokens to purchase.
    function priceFor(uint96 lotId_, uint256 payout_) public view override returns (uint256) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Check that payout does not exceed remaining capacity
        if (payout_ > lot.capacity) {
            revert Auction_InsufficientCapacity();
        }

        // Convert payout to UD60x18. We scale first to 18 decimals from the payout token decimals
        uint256 baseTokenScale = 10 ** lot.baseTokenDecimals;
        UD60x18 payout = ud(payout_.mulDiv(uUNIT, baseTokenScale));

        // Calculate the first numerator factor: (q0 - qm), if qm is zero, this is q0
        // In the auction creation, we checked that the equilibrium price is greater than the minimum price
        // Scale the result to 18 decimals
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        UD60x18 priceDiff =
            ud((auction.equilibriumPrice - auction.minimumPrice).fullMulDiv(uUNIT, quoteTokenScale));

        // Calculate the second numerator factor: e^((k*P)/r) - 1
        UD60x18 ekpr = auction.decayConstant.mul(payout).div(auction.emissionsRate).exp().sub(UNIT);

        // Handle cases of T being positive or negative
        UD60x18 result;
        if (block.timestamp >= auction.lastAuctionStart) {
            // T is positive
            // Calculate the denominator: ke^(k*T)
            UD60x18 kekt = auction.decayConstant.mul(
                convert(block.timestamp - auction.lastAuctionStart)
            ).exp().mul(auction.decayConstant);

            // Calculate the first term in the formula
            result = priceDiff.mul(ekpr).div(kekt);
        } else {
            // T is negative: flip the e^(k * T) term to the numerator

            // Calculate the exponential: e^(k*T)
            UD60x18 ekt =
                auction.decayConstant.mul(convert(auction.lastAuctionStart - block.timestamp)).exp();

            // Calculate the first term in the formula
            result = priceDiff.mul(ekpr).mul(ekt).div(auction.decayConstant);
        }

        // If minimum price is zero, then the first term is the result, otherwise we add the second term
        if (auction.minimumPrice > 0) {
            UD60x18 minPrice = ud(auction.minimumPrice.mulDiv(uUNIT, quoteTokenScale));
            result = result + minPrice.mul(payout).div(auction.emissionsRate);
        }

        // Scale price back to quote token decimals
        uint256 amount = result.intoUint256().fullMulDiv(quoteTokenScale, uUNIT);

        return amount;
    }

    function payoutFor(uint96 lotId_, uint256 amount_) public view override returns (uint256) {
        // Calculate the payout and emissions
        uint256 payout;
        (payout,) = _payoutAndEmissionsFor(lotId_, amount_);

        // Check that payout does not exceed remaining capacity
        if (payout > lotData[lotId_].capacity) {
            revert Auction_InsufficientCapacity();
        }

        return payout;
    }

    // Two cases:
    //
    // 1. Minimum price is zero
    // P = (r * ln((Q * k * e^(k*T) / q0) + 1)) / k
    // where P is the number of payout tokens, Q is the number of quote tokens,
    // r is the emissions rate, k is the decay constant, q0 is the equilibrium price of the auction,
    // and T is the time since the last auction start
    //
    // 2. Minimum price is not zero
    // P = (r * (k * Q / qm + C - W(C e^(k * Q / qm + C)))) / k
    // where P is the number of payout tokens, Q is the number of quote tokens,
    // r is the emissions rate, k is the decay constant, qm is the minimum price of the auction,
    // q0 is the equilibrium price of the auction, T is the time since the last auction start,
    // C = (q0 - qm)/(qm * e^(k * T)), and W is the Lambert-W function (productLn).
    function _payoutAndEmissionsFor(
        uint96 lotId_,
        uint256 amount_
    ) internal view returns (uint256, uint256) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Get quote token scale and convert equilibrium price to 18 decimals
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        UD60x18 q0 = ud(auction.equilibriumPrice.fullMulDiv(uUNIT, quoteTokenScale));

        // Scale amount to 18 decimals
        UD60x18 amount = ud(amount_.mulDiv(uUNIT, quoteTokenScale));

        // Factors are calculated in a certain order to avoid precision loss
        UD60x18 payout;
        if (auction.minimumPrice == 0) {
            UD60x18 logFactor;
            if (block.timestamp >= auction.lastAuctionStart) {
                // T is positive
                // Calculate the exponential factor
                UD60x18 ekt = auction.decayConstant.mul(
                    convert(block.timestamp - auction.lastAuctionStart)
                ).exp();

                // Calculate the logarithm
                // Operand is guaranteed to be >= 1, so the result is positive
                logFactor = amount.mul(auction.decayConstant).mul(ekt).div(q0).add(UNIT).ln();
            } else {
                // T is negative: flip the e^(k * T) term to the denominator

                // Calculate the exponential factor
                UD60x18 ekt = auction.decayConstant.mul(
                    convert(auction.lastAuctionStart - block.timestamp)
                ).exp();

                // Calculate the logarithm
                // Operand is guaranteed to be >= 1, so the result is positive
                logFactor = amount.mul(auction.decayConstant).div(ekt.mul(q0)).add(UNIT).ln();
            }

            // Calculate the payout
            payout = auction.emissionsRate.mul(logFactor).div(auction.decayConstant);
        } else {
            // TODO think about refactoring to avoid precision loss

            {
                // Check that the amount / minPrice is not greater than the max payout (i.e. remaining capacity)
                uint256 minPrice = auction.minimumPrice;
                uint256 payoutAtMinPrice = FixedPointMathLib.fullMulDiv(
                    amount_, 10 ** lotData[lotId_].baseTokenDecimals, minPrice
                );
                if (payoutAtMinPrice > maxPayout(lotId_)) {
                    revert Auction_InsufficientCapacity();
                }
            }

            // Convert minimum price to 18 decimals
            // Can't overflow because quoteTokenScale <= uUNIT
            UD60x18 qm = ud(auction.minimumPrice.fullMulDiv(uUNIT, quoteTokenScale));

            // Calculate first term:  (k * Q) / qm
            UD60x18 f = auction.decayConstant.mul(amount).div(qm);

            // Calculate second term aka C: (q0 - qm)/(qm * e^(k * T))
            UD60x18 c;
            if (block.timestamp >= auction.lastAuctionStart) {
                // T is positive
                c = q0.sub(qm).div(
                    auction.decayConstant.mul(convert(block.timestamp - auction.lastAuctionStart))
                        .exp().mul(qm)
                );
            } else {
                // T is negative: flip the e^(k * T) term to the numerator
                c = q0.sub(qm).mul(
                    auction.decayConstant.mul(convert(auction.lastAuctionStart - block.timestamp))
                        .exp()
                ).div(qm);
            }

            // Calculate the third term: W(C e^(k * Q / qm + C))
            UD60x18 w = c.add(f).exp().mul(c).productLn();

            // Calculate payout
            // The intermediate term (f + c - w) cannot underflow because
            // firstTerm + c - thirdTerm >= 0 for all amounts >= 0.
            //
            // Proof:
            // 1. k > 0, Q >= 0, qm > 0 => f >= 0
            // 2. q0 > qm, qm > 0 => c >= 0
            // 3. f + c = W((f + c) * e^(f + c))
            // 4. 1 & 2 => f + c >= 0, f + c >= f, f + c >= c
            // 5. W(x) is monotonically increasing for x >= 0
            // 6. 4 & 5 => W((f + c) * e^(f + c)) >= W(c * e^(f + c))
            // 7. 3 & 6 => f + c >= W(c * e^(f + c))
            // QED
            payout = auction.emissionsRate.mul(f.add(c).sub(w)).div(auction.decayConstant);
        }

        // Calculate seconds of emissions from payout
        uint256 secondsOfEmissions = payout.div(auction.emissionsRate).intoUint256();

        // Scale payout to payout token decimals and return
        return (payout.intoUint256().mulDiv(10 ** lot.baseTokenDecimals, uUNIT), secondsOfEmissions);
    }

    function maxPayout(uint96 lotId_) public view override returns (uint256) {
        // The max payout is the remaining capacity of the lot
        return lotData[lotId_].capacity;
    }

    function maxAmountAccepted(uint96 lotId_) external view override returns (uint256) {
        // The max amount accepted is the price to purchase the remaining capacity of the lot
        return priceFor(lotId_, lotData[lotId_].capacity);
    }
}
