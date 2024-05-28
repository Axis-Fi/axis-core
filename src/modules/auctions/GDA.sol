// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Protocol dependencies
import {Module} from "src/modules/Modules.sol";
import {AuctionModule} from "src/modules/Auction.sol";
import {Veecode, toVeecode} from "src/modules/Modules.sol";
import {AtomicAuctionModule} from "src/modules/auctions/AtomicAuctionModule.sol";
import {IGradualDutchAuction} from "src/interfaces/modules/auctions/IGradualDutchAuction.sol";

// External libraries
import {
    UD60x18, ud, convert, UNIT, uUNIT, EXP_MAX_INPUT, ZERO, HALF_UNIT, MAX_UD60x18
} from "lib/prb-math/src/UD60x18.sol";
import "lib/prb-math/src/Common.sol" as PRBMath;

import {console2} from "lib/forge-std/src/console2.sol";

/// @notice Continuous Gradual Dutch Auction (GDA) module with exponential decay and a minimum price.
contract GradualDutchAuction is IGradualDutchAuction, AtomicAuctionModule {
    using {PRBMath.mulDiv} for uint256;

    // ========== STATE VARIABLES ========== //
    /* solhint-disable private-vars-leading-underscore */
    UD60x18 internal constant ONE_DAY = UD60x18.wrap(1 days * uUNIT);

    // Decay target over the first period must fit within these bounds
    // We use 18 decimals so we don't have to convert it to use as a UD60x18
    uint256 internal constant MIN_DECAY_TARGET = 1e16; // 1%
    uint256 internal constant MAX_DECAY_TARGET = 49e16; // 49%

    // Bounds for the decay period, which establishes the bounds for the decay constant
    // If a you want a longer or shorter period for the target, you can find another point on the curve that is in this range
    // and calculate the decay target for that point as your input
    uint48 internal constant MIN_DECAY_PERIOD = 6 hours;
    uint48 internal constant MAX_DECAY_PERIOD = 1 weeks;

    // Decay period must be greater than or equal to 1 day and less than or equal to 1 week
    // A minimum value of q1 = q0 * 0.01 and a min period of 1 day means:
    // MAX_LN_OUTPUT = ln(1/0.51) = 0_673344553263765596
    // MAX_DECAY_CONSTANT = MAX_LN_OUTPUT * 24 = 16_160269278330374304
    // -> For auctions without a min price, implies a max duration of 8 days in the worst case (decaying 49% over an hour)
    // -> For auctions with a min price, implies a max duration of 0.302 days (7.25 hours) in the worst case (decaying 49% over an hour)
    // A maximum value of q1 = q0 * 0.99 and a max period of 7 days means:
    // MIN_LN_OUTPUT = ln(1/0.99) = 0_010050335853501441
    // MIN_LN_OUTPUT / 7 = 0_001435762264785920
    // -> For auctions without a min price, implies a max duration of ~52 years in the best case (decaying 1% over a week)
    // -> For auctions with a min price, implies a max duration of ~9 years in the best case (decaying 1% over a week)

    // Precomputed: ln(133.084258667509499440) = 4.890982451446117211 using the PRBMath ln function (off by 10 wei)
    UD60x18 internal constant LN_OF_EXP_MAX_INPUT = UD60x18.wrap(4_890982451446117211);

    /* solhint-enable private-vars-leading-underscore */

    mapping(uint96 lotId => AuctionData data) public auctionData;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // Initially setting the minimum GDA duration to 1 hour
        minAuctionDuration = 1 hours;
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
        // Validate price and capacity values are large enough to avoid precision errors
        // We do this by requiring them to be atleast 10^(tokenDecimals / 2), we round up to make it more strict.
        // This sets a floor value for the price of:
        // - 10^-9 quote tokens per base token when quote decimals are 18.
        // - 10^-5 quote tokens per base token when quote decimals are 9.
        // - 10^-3 quote tokens per base token when quote decimals are 6.
        // This sets a floor value for capacity of:
        // - 10^9 base tokens when base decimals are 18.
        // - 10^5 base tokens when base decimals are 9.
        // - 10^3 base tokens when base decimals are 6.
        {
            int8 priceDecimals = _getValueDecimals(params.equilibriumPrice, lot_.quoteTokenDecimals);
            int8 capacityDecimals = _getValueDecimals(lot_.capacity, lot_.baseTokenDecimals);

            uint8 halfQuoteDecimals = lot_.quoteTokenDecimals % 2 == 0 ? lot_.quoteTokenDecimals / 2 : lot_.quoteTokenDecimals / 2 + 1;
            uint8 halfBaseDecimals = lot_.baseTokenDecimals % 2 == 0 ? lot_.baseTokenDecimals / 2 : lot_.baseTokenDecimals / 2 + 1;

            if (priceDecimals < - int8(halfQuoteDecimals)
                || capacityDecimals < - int8(halfBaseDecimals)) {
                revert Auction_InvalidParams();
            }

            // Also validate the minimum price if it is not zero
            if (params.minimumPrice > 0) {
                int8 minPriceDecimals = _getValueDecimals(params.minimumPrice, lot_.quoteTokenDecimals);
                if (minPriceDecimals < - int8(halfQuoteDecimals)) {
                    revert Auction_InvalidParams();
                }
            }
        }

        // Equilibrium Price less than u128 max
        // This sets a fairly high ceiling:
        // 2^128 - 1 / 10^18 = 34.028*10^38 / 10^18 = max price 34.028*10^20
        // quote tokens per base token when quote token decimals are 18.
        if (params.equilibriumPrice > type(uint128).max) {
            revert Auction_InvalidParams();
        }

        // Capacity must be in base token
        if (lot_.capacityInQuote) revert Auction_InvalidParams();

        // Capacity must at least as large as the auction duration so that the emissions rate is not zero
        // and no larger than u128 max to avoid various math errors
        if (
            lot_.capacity < uint256(lot_.conclusion - lot_.start)
                || lot_.capacity > type(uint128).max
        ) {
            revert Auction_InvalidParams();
        }

        // Minimum price can be zero, but the equations default back to the basic GDA implementation

        // Validate the decay parameters and calculate the decay constant
        // k = ln((q0 - qm) / (q1 - qm)) / dp
        // require q0 > q1 > qm
        // q1 = q0 * (1 - d1)
        if (params.decayTarget > MAX_DECAY_TARGET || params.decayTarget < MIN_DECAY_TARGET) {
            revert Auction_InvalidParams();
        }

        // Decay period must be between the set bounds
        // These bounds also ensure the decay constant is not zero
        if (params.decayPeriod < MIN_DECAY_PERIOD || params.decayPeriod > MAX_DECAY_PERIOD) {
            revert Auction_InvalidParams();
        }

        UD60x18 decayConstant;
        UD60x18 q0;
        UD60x18 qm;
        {
            uint256 quoteTokenScale = 10 ** lot_.quoteTokenDecimals;
            q0 = ud(params.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale));
            UD60x18 q1 = q0.mul(UNIT - ud(params.decayTarget)).div(UNIT);
            qm = ud(params.minimumPrice.mulDiv(uUNIT, quoteTokenScale));
            console2.log("q0:", q0.unwrap());
            console2.log("q1:", q1.unwrap());
            console2.log("qm:", qm.unwrap());

            // Check that q0 > 0.99q0 >= q1 > 0.99q1 => qm
            // Don't need to check q0 > 0.99q0 >= q1 since:
            //   decayTarget >= 1e16 => q0 * 0.99 >= q1
            // This ensures that the operand for the logarithm is positive
            // We enforce a minimum difference for q1 and qm as well to avoid small dividends.
            if (q1 - qm < ud(1e16)) {
                revert Auction_InvalidParams();
            }

            // If qm is not zero, then we require that it be not less than half of q0
            // This is to ensure that we do not exceed the maximum input for the exponential function
            // It is also a sane default.
            // Another piece of this check is done during a purchase to make sure that the amount
            // provided is does not exceed the price of the capacity.
            if (qm > ZERO && qm < q0.mul(HALF_UNIT)) {
                revert Auction_InvalidParams();
            }

            // Calculate the decay constant
            decayConstant =
                (q0 - qm).div(q1 - qm).ln().div(convert(params.decayPeriod).div(ONE_DAY));
            console2.log("decay constant:", decayConstant.unwrap());
        }

        // TODO other validation checks?

        // Calculate duration of the auction in days
        UD60x18 duration = convert(uint256(lot_.conclusion - lot_.start)).div(ONE_DAY);
        console2.log("duration:", duration.unwrap());

        // The duration must be less than the max exponential input divided by the decay constant
        // in order for the exponential operations to not overflow. See the minimum and maximum
        // constant calculations for more information.
        if (qm == ZERO && duration > EXP_MAX_INPUT.div(decayConstant)) {
            revert Auction_InvalidParams();
        }
        // In the case of a non-zero min price, the duration must be less than the natural logarithm
        // of the max input divided by the decay constant to avoid overflows in the operand of the W function.
        if (qm > ZERO && duration > LN_OF_EXP_MAX_INPUT.div(decayConstant)) {
            revert Auction_InvalidParams();
        }

        // Calculate emissions rate as number of tokens released per day
        UD60x18 emissionsRate =
            ud(lot_.capacity.mulDiv(uUNIT, 10 ** lot_.baseTokenDecimals)).div(duration);
        console2.log("emissions rate:", emissionsRate.unwrap());

        // To avoid divide by zero issues, we also must check that:
        // if qm is zero, then q0 * r > 0
        // if qm is not zero, then qm * r > 0, which also implies the other.
        if (qm == ZERO && q0.mul(emissionsRate) == ZERO) {
            revert Auction_InvalidParams();
        }

        if (qm > ZERO && qm.mul(emissionsRate) == ZERO) {
            revert Auction_InvalidParams();
        }

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

    // For Continuous GDAs with exponential decay, the price of a given token t seconds after being emitted is:
    // q(t) = r * (q0 - qm) * e^(-k*t) + qm
    // where k is the decay constant, q0 is the initial price, and qm is the minimum price
    // Integrating this function from the last auction start time for a particular number of tokens,
    // gives the multiplier for the token price to determine amount of quote tokens required to purchase:
    // Q(T) = (r * (q0 - qm) * (e^((k*P)/r) - 1)) / ke^(k*T) + (qm * P)
    // where T is the time since the last auction start, P is the number of payout tokens to purchase,
    // and r is the emissions rate (number of tokens released per second).
    //
    // If qm is 0, then the equation simplifies to:
    // q(t) = r * q0 * e^(-k*t)
    // Integrating this function from the last auction start time for a particular number of tokens,
    // gives the multiplier for the token price to determine amount of quote tokens required to purchase:
    // Q(T) = (r * q0 * (e^((k*P)/r) - 1)) / ke^(k*T)
    // where T is the time since the last auction start, P is the number of payout tokens to purchase.
    //
    // Note: this function is an estimate. The actual price returned will vary some due to the precision of the calculations.
    function priceFor(uint96 lotId_, uint256 payout_) public view override returns (uint256) {
        // Lot ID must be valid
        _revertIfLotInvalid(lotId_);

        // Get lot and auction data
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
        UD60x18 priceDiff = ud(
            (auction.equilibriumPrice - auction.minimumPrice).mulDiv(uUNIT, quoteTokenScale)
        ).mul(auction.emissionsRate);
        console2.log("price diff:", priceDiff.unwrap());

        // Calculate the second numerator factor: e^((k*P)/r) - 1
        // This cannot exceed the max exponential input due to the bounds imbosed on auction creation
        // emissions rate = initial capacity / duration
        // payout must be less then or equal to initial capacity
        // therefore, the resulting exponent is at most decay constant * duration
        UD60x18 ekpr = auction.decayConstant.mul(payout).div(auction.emissionsRate).exp().sub(UNIT);
        console2.log("ekpr:", ekpr.unwrap());

        // Handle cases of T being positive or negative
        UD60x18 result;
        if (block.timestamp >= auction.lastAuctionStart) {
            // T is positive
            // Calculate the denominator: ke^(k*T)
            // This cannot exceed the max exponential input due to the bounds imbosed on auction creation
            // Current time - last auction start is guaranteed to be < duration. If not, the auction is over.
            UD60x18 kekt = auction.decayConstant.mul(
                convert(block.timestamp - auction.lastAuctionStart).div(ONE_DAY)
            ).exp().mul(auction.decayConstant);
            console2.log("kekt:", kekt.unwrap());

            // Calculate the first term in the formula
            result = priceDiff.mul(ekpr).div(kekt);
            console2.log("result:", result.unwrap());
        } else {
            // T is negative: flip the e^(k * T) term to the numerator

            // Calculate the exponential: e^(k*T)
            // This cannot exceed the max exponential input due to the bounds imbosed on auction creation
            // last auction start - current time is guaranteed to be < duration. If not, the auction is over.
            UD60x18 ekt = auction.decayConstant.mul(
                convert(auction.lastAuctionStart - block.timestamp)
            ).div(ONE_DAY).exp();
            console2.log("ekt:", ekt.unwrap());

            // Calculate the first term in the formula
            result = priceDiff.mul(ekpr).mul(ekt).div(auction.decayConstant);
            console2.log("result:", result.unwrap());
        }

        // If minimum price is zero, then the first term is the result, otherwise we add the second term
        if (auction.minimumPrice > 0) {
            UD60x18 minPrice = ud(auction.minimumPrice.mulDiv(uUNIT, quoteTokenScale));
            result = result + minPrice.mul(payout);
            console2.log("result with min price", result.unwrap());
        }

        // Scale price back to quote token decimals
        uint256 amount = result.intoUint256().mulDiv(quoteTokenScale, uUNIT);

        return amount;
    }

    function payoutFor(uint96 lotId_, uint256 amount_) public view override returns (uint256) {
        // Lot ID must be valid
        _revertIfLotInvalid(lotId_);

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
    // P = (r * ln((Q * k * e^(k*T) / (r * q0)) + 1)) / k
    // where P is the number of payout tokens, Q is the number of quote tokens,
    // r is the emissions rate, k is the decay constant, q0 is the equilibrium price of the auction,
    // and T is the time since the last auction start
    //
    // 2. Minimum price is not zero
    // P = (r * ((k * Q) / (r * qm) + C - W(C e^((k * Q) / (r * qm) + C)))) / k
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

        // Ensure the amount does not exceed the max amount accepted
        uint256 maxAmount = maxAmountAccepted(lotId_);
        if (amount_ > maxAmount) {
            revert Auction_InsufficientCapacity();
        }

        // Get quote token scale and convert equilibrium price to 18 decimals
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        UD60x18 q0 = ud(auction.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale));

        // Scale amount to 18 decimals
        UD60x18 amount = ud(amount_.mulDiv(uUNIT, quoteTokenScale));

        // Factors are calculated in a certain order to avoid precision loss
        UD60x18 payout;
        if (auction.minimumPrice == 0) {
            // Auction does not have a minimum price
            UD60x18 logFactor;
            if (block.timestamp >= auction.lastAuctionStart) {
                // T is positive
                // Calculate the exponential factor
                // This cannot exceed the max exponential input due to the bounds imbosed on auction creation
                // Current time - last auction start is guaranteed to be < duration. If not, the auction is over.
                UD60x18 ekt = auction.decayConstant.mul(
                    convert(block.timestamp - auction.lastAuctionStart).div(ONE_DAY)
                ).exp();
                console2.log("ekt:", ekt.unwrap());
                console2.log("r * q0:", auction.emissionsRate.mul(q0).unwrap());

                // Calculate the logarithm
                // Operand is guaranteed to be >= 1, so the result is positive
                logFactor = amount.mul(auction.decayConstant).mul(ekt).div(
                    auction.emissionsRate.mul(q0)
                ).add(UNIT).ln();
            } else {
                // T is negative: flip the e^(k * T) term to the denominator

                // Calculate the exponential factor
                // This cannot exceed the max exponential input due to the bounds imbosed on auction creation
                // last auction start - current time is guaranteed to be < duration. If not, the auction is over.
                UD60x18 ekt = auction.decayConstant.mul(
                    convert(auction.lastAuctionStart - block.timestamp)
                ).exp();
                console2.log("ekt:", ekt.unwrap());

                // Calculate the logarithm
                // Operand is guaranteed to be >= 1, so the result is positive
                logFactor = amount.mul(auction.decayConstant).div(
                    ekt.mul(auction.emissionsRate).mul(q0)
                ).add(UNIT).ln();
            }

            // Calculate the payout
            payout = auction.emissionsRate.mul(logFactor).div(auction.decayConstant);
        } else {
            // Auction has a minimum price

            // Convert minimum price to 18 decimals
            // Can't overflow because quoteTokenScale <= uUNIT
            UD60x18 qm = ud(auction.minimumPrice.mulDiv(uUNIT, quoteTokenScale));

            // Calculate first term aka F:  (k * Q) / (r * qm)
            UD60x18 f = auction.decayConstant.mul(amount).div(auction.emissionsRate.mul(qm));
            console2.log("first term:", f.unwrap());

            // Calculate second term aka C: (q0 - qm)/(qm * e^(k * T))
            UD60x18 c;
            if (block.timestamp >= auction.lastAuctionStart) {
                // T is positive
                // This cannot exceed the max exponential input due to the bounds imbosed on auction creation
                // Current time - last auction start is guaranteed to be < duration. If not, the auction is over.
                // We have to divide twice to avoid multipling the exponential result by qm, which could overflow.
                c = q0.sub(qm).div(qm).div(
                    auction.decayConstant.mul(
                        convert(block.timestamp - auction.lastAuctionStart).div(ONE_DAY)
                    ).exp()
                );
            } else {
                // T is negative: flip the e^(k * T) term to the numerator
                // This cannot exceed the max exponential input due to the bounds imbosed on auction creation
                // last auction start - current time is guaranteed to be < duration. If not, the auction is over.
                // We divide before multiplying here to avoid reduce the odds of an intermediate result overflowing.
                c = q0.sub(qm).div(qm).mul(
                    auction.decayConstant.mul(
                        convert(auction.lastAuctionStart - block.timestamp).div(ONE_DAY)
                    ).exp()
                );
            }
            console2.log("second term:", c.unwrap());

            // Calculate the third term: W(C e^(F + C))
            // 17 wei is the maximum error for values in the
            // range of possible values for the lambert-W approximation,
            // this makes sure the estimate is conservative.
            // 
            // We prevent overflow in the operand of the W function via the duration < LN_OF_EXP_MAX_INPUT / decayConstant check.
            // This means that e^(f + c) will always be < EXP_MAX_INPUT / c.
            // We check for overflow before adding the error correction.
            UD60x18 w = c.add(f).exp().mul(c).productLn();
            {
                UD60x18 err = ud(17);
                w = w > MAX_UD60x18.sub(err) ? MAX_UD60x18 : w.add(err);
            }
            console2.log("third term:", w.unwrap());

            // Without error correction, the intermediate term (f + c - w) cannot underflow because
            // firstTerm + c - thirdTerm >= 0 for all amounts >= 0.
            //
            // Proof:
            // 1. k > 0, Q >= 0, r > 0, qm > 0 => f >= 0
            // 2. q0 > qm, qm > 0 => c >= 0
            // 3. f + c = W((f + c) * e^(f + c))
            // 4. 1 & 2 => f + c >= 0, f + c >= f, f + c >= c
            // 5. W(x) is monotonically increasing for x >= 0
            // 6. 4 & 5 => W((f + c) * e^(f + c)) >= W(c * e^(f + c))
            // 7. 3 & 6 => f + c >= W(c * e^(f + c))
            // QED
            //
            // However, it is possible since we add a small correction to w.
            // Therefore, we check for underflow on the term and set a floor at 0.
            UD60x18 fcw = w > f.add(c) ? ZERO : f.add(c).sub(w);
            payout = auction.emissionsRate.mul(fcw).div(auction.decayConstant);
            console2.log("sum of terms:", fcw.unwrap());
            console2.log("emissions rate:", auction.emissionsRate.unwrap());
            console2.log("decay constant:", auction.decayConstant.unwrap());
            console2.log("payout:", payout.unwrap());
        }

        // Calculate seconds of emissions from payout
        uint256 secondsOfEmissions = convert(payout.div(auction.emissionsRate.mul(ONE_DAY)));

        // Scale payout to payout token decimals and return
        return (payout.intoUint256().mulDiv(10 ** lot.baseTokenDecimals, uUNIT), secondsOfEmissions);
    }

    function maxPayout(uint96 lotId_) external view override returns (uint256) {
        // Lot ID must be valid
        _revertIfLotInvalid(lotId_);

        // The max payout is the remaining capacity of the lot
        return lotData[lotId_].capacity;
    }

    function maxAmountAccepted(uint96 lotId_) public view override returns (uint256) {
        // The max amount accepted is the price to purchase the remaining capacity of the lot
        // This function checks if the lot ID is valid
        return priceFor(lotId_, lotData[lotId_].capacity);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice         Helper function to calculate number of value decimals based on the stated token decimals.
    /// @param value_   The value to calculate the number of decimals for
    /// @return         The number of decimals
    function _getValueDecimals(uint256 value_, uint8 tokenDecimals_) internal pure returns (int8) {
        int8 decimals;
        while (value_ >= 10) {
            value_ = value_ / 10;
            decimals++;
        }

        // Subtract the stated decimals from the calculated decimals to get the relative value decimals.
        // Required to do it this way vs. normalizing at the beginning since value decimals can be negative.
        return decimals - int8(tokenDecimals_);
    }
}
