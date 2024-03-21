/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// Protocol dependencies
import {AtomicAuctionModule} from "src/modules/auctions/bases/AtomicAuctionModule.sol";

// Libraries
import {SD59x18, sd, convert, ZERO, UNIT} from "lib/prb-math/src/SD59x18.sol";
import {FullMath} from "src/lib/FullMath.sol";

contract GradualDutchAuctionModule is AtomicAuctionModule {
    using FullMath for uint256;

    // ========== DATA STRUCTURES ========== //

    enum Decay {
        Linear,
        Exponential
    }

    /// @notice Auction pricing data
    struct AuctionData {
        uint256 equilibriumPrice; // price at which the auction is balanced
        uint48 lastAuctionStart;
        Decay decayType; // type of decay to use for the market
        SD59x18 decayConstant; // speed at which the price decays, as SD59x18.
        SD59x18 emissionsRate; // number of tokens released per second, as SD59x18. Calculated as capacity / duration.
    }

    struct GDAParams {
        uint256 equilibriumPrice;
        SD59x18 decayConstant;
        Decay decayType;
    }

    // ========== STATE VARIABLES ========== //

    SD59x18 internal constant _NEGATIVE_UNIT = SD59x18.wrap(int256(-1e18));
    uint256 internal constant _uUNIT = 1e18;

    mapping(uint256 id => AuctionData data) public auctionData;

    // ========== SETUP ========== //
    constructor(address auctionHouse_) AtomicAuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day initially
        minAuctionDuration = 1 days;
    }

    // ========== AUCTION ========== //

    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override {
        // Decode implementation parameters
        GDAParams memory params = abi.decode(params_, (GDAParams));

        // Validate parameters
        // Price must not be zero
        if (params.equilibriumPrice == 0) revert Auction_InvalidParams();

        // Validate the decay constant
        // The maximum value is enforced by decoding to the SD59x18 type
        // Regardless of decay type, decay constant must be positive
        if (params.decayConstant <= ZERO) revert Auction_InvalidParams();

        // If linear decay, the decay constant must not be greater 1/duration
        SD59x18 duration = convert(int256(uint256(lot_.conclusion - lot_.start)));
        if (params.decayType == Decay.Linear && params.decayConstant > UNIT.div(duration)) {
            revert Auction_InvalidParams();
        }

        // Calculate emissions rate
        SD59x18 emissionsRate =
            sd(int256(lot_.capacity * uUNIT / 10 ** lot_.baseTokenDecimals)).div(duration);

        // Store auction data
        AuctionData storage data = auctionData[lotId_];
        data.equilibriumPrice = params.equilibriumPrice;
        data.decayType = params.decayType;
        data.decayConstant = params.decayConstant;
        data.emissionsRate = emissionsRate;
    }

    // Do not need to do anything extra here
    function _cancelAuction(uint96 lotId_) internal override {}

    // ========== PURCHASE ========== //

    function _purchase(
        uint96 lotId_,
        uint96 amount_,
        bytes calldata
    ) internal override returns (uint96 payout, bytes memory auctionOutput) {
        // Calculate the payout and emissions
        (uint256 payout256, uint48 secondsOfEmissions) = _payoutAndEmissionsFor(lotId_, amount_);
        payout = uint96(payout256); // TODO figure out how we want to handle casting.

        // Update last auction start with seconds of emissions
        // Do not have to check that too many seconds have passed here
        // since payout/amount is checked against capacity in the top-level function
        auctionData[lotId_].lastAuctionStart += secondsOfEmissions;

        // Return the payout and emissions
        return (payout, bytes(""));
    }

    /* ========== PRICE FUNCTIONS ========== */

    function priceFor(uint96 lotId_, uint96 payout_) public view override returns (uint96) {
        Decay decayType = auctionData[lotId_].decayType;

        uint256 amount256;
        if (decayType == Decay.Exponential) {
            amount256 = _exponentialPriceFor(lotId_, uint256(payout_));
        } else if (decayType == Decay.Linear) {
            amount256 = _linearPriceFor(lotId_, uint256(payout_));
        }
        uint96 amount = uint96(amount256); // TODO figure out how we want to handle casting.

        // Check that amount in or payout do not exceed remaining capacity
        Lot memory lot = lotData[lotId_];
        if (lot.capacityInQuote ? amount > lot.capacity : payout_ > lot.capacity) {
            revert Auction_InsufficientCapacity();
        }

        return amount;
    }

    // For Continuos GDAs with exponential decay, the price of a given token t seconds after being emitted is:
    // p(t) = p0 * e^(-k*t)
    // Integrating this function from the last auction start time for a particular number of tokens,
    // gives the multiplier for the token price to determine amount of quote tokens required to purchase:
    // P(T) = (p0 / k) * (e^(-k*q) - 1) / e^(-k*T)
    // where T is the time since the last auction start, q is the number of tokens to purchase, and p0 is the initial price.
    function _exponentialPriceFor(uint96 lotId_, uint256 payout_) internal view returns (uint256) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Convert payout to SD59x18. We scale first to 18 decimals from the payout token decimals
        uint256 baseTokenScale = 10 ** lot.baseTokenDecimals;
        SD59x18 payout = sd(int256(payout_.mulDiv(uUNIT, baseTokenScale)));

        // Calculate time since last auction start
        SD59x18 timeSinceLastAuctionStart =
            convert(int256(block.timestamp - uint256(auction.lastAuctionStart)));

        // Calculate the first numerator factor
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        SD59x18 num1 = sd(int256(auction.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale))).div(
            auction.decayConstant
        );

        // Calculate the second numerator factor
        SD59x18 num2 = auction.decayConstant.mul(NEGATIVE_UNIT).mul(payout).exp().sub(UNIT);

        // Calculate the denominator
        SD59x18 denominator =
            auction.decayConstant.mul(NEGATIVE_UNIT).mul(timeSinceLastAuctionStart).exp();

        // Calculate return value
        // This value should always be positive, therefore, we can safely cast to uint256
        // We scale the return value back to payout token decimals
        return num1.mul(num2).div(denominator).intoUint256().mulDiv(baseTokenScale, uUNIT);
    }

    // p(t) = p0 * (1 - k*t)
    // where p0 is the initial price, k is the decay constant, and t is the time since the last auction start
    // P(T) = (p0 * q / r) * (1 - k*T + k*q/2r)
    // where T is the time since the last auction start, q is the number of tokens to purchase,
    // r is the emissions rate, and p0 is the initial price
    function _linearPriceFor(uint96 lotId_, uint256 payout_) internal view returns (uint256) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Convert payout to SD59x18. We scale first to 18 decimals from the payout token decimals
        uint256 baseTokenScale = 10 ** lot.baseTokenDecimals;
        SD59x18 payout = sd(int256(payout_.mulDiv(uUNIT, baseTokenScale)));

        // Calculate time since last auction start
        SD59x18 timeSinceLastAuctionStart =
            convert(int256(block.timestamp - uint256(auction.lastAuctionStart)));

        // Calculate decay factor
        // TODO can we confirm this will be positive?
        SD59x18 decayFactor = UNIT.sub(auction.decayConstant.mul(timeSinceLastAuctionStart)).add(
            auction.decayConstant.mul(payout).div(convert(int256(2)).mul(auction.emissionsRate))
        );

        // Calculate payout factor
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        SD59x18 payoutFactor =
            payout.mul(sd(int256(auction.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale))));

        // Calculate final return value and convert back to market scale
        return payoutFactor.mul(decayFactor).div(auction.emissionsRate).intoUint256().mulDiv(
            quoteTokenScale, uUNIT
        );
    }

    /* ========== PAYOUT CALCULATIONS ========== */

    function payoutFor(uint96 lotId_, uint96 amount_) public view override returns (uint96) {
        Lot memory lot = lotData[lotId_];

        (uint256 payout256,) = _payoutAndEmissionsFor(lotId_, uint256(amount_));
        uint96 payout = uint96(payout256); // TODO figure out how we want to handle casting.

        // Check that amount in or payout do not exceed remaining capacity
        if (lot.capacityInQuote ? amount_ > lot.capacity : payout > lot.capacity) {
            revert Auction_InsufficientCapacity();
        }

        return payout;
    }

    function _payoutAndEmissionsFor(
        uint96 lotId_,
        uint256 amount_
    ) internal view returns (uint256, uint48) {
        Decay decayType = auctionData[lotId_].decayType;

        if (decayType == Decay.Exponential) {
            return _payoutForExpDecay(lotId_, amount_);
        } else if (decayType == Decay.Linear) {
            return _payoutForLinearDecay(lotId_, amount_);
        } else {
            revert Auction_InvalidParams();
        }
    }

    // P = (r / k) * ln(Q * k / p0 * e^(k*T) + 1)
    // where P is the number of payout tokens, Q is the number of quote tokens,
    // r is the emissions rate, k is the decay constant, p0 is the price target of the market,
    // and T is the time since the last auction start
    function _payoutForExpDecay(
        uint96 lotId_,
        uint256 amount_
    ) internal view returns (uint256, uint48) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Convert to 18 decimals for fixed math by pre-computing the Q / p0 factor (which is in payout token units)
        // and then scaling using payout token decimals
        SD59x18 payout;
        uint256 baseTokenScale = 10 ** lot.baseTokenDecimals;
        {
            SD59x18 scaledQ = sd(
                int256(
                    amount_.mulDiv(10 ** lot.quoteTokenDecimals, auction.equilibriumPrice).mulDiv(
                        uUNIT, baseTokenScale
                    )
                )
            );

            // Calculate time since last auction start
            SD59x18 timeSinceLastAuctionStart =
                convert(int256(block.timestamp - uint256(auction.lastAuctionStart)));

            // Calculate the logarithm
            SD59x18 logFactor = auction.decayConstant.mul(timeSinceLastAuctionStart).exp().mul(
                scaledQ
            ).mul(auction.decayConstant).add(UNIT).ln();

            // Calculate the payout
            payout = logFactor.mul(auction.emissionsRate).div(auction.decayConstant);
        }

        // Calculate seconds of emissions from payout or amount (depending on capacity type)
        uint48 secondsOfEmissions;
        if (lot.capacityInQuote) {
            // Convert amount to SD59x18
            SD59x18 amount = sd(int256(amount_.mulDiv(uUNIT, 10 ** lot.quoteTokenDecimals)));
            // TODO need to think about overflows on this cast
            secondsOfEmissions = uint48(amount.div(auction.emissionsRate).intoUint256());
        } else {
            secondsOfEmissions = uint48(payout.div(auction.emissionsRate).intoUint256());
        }

        // Scale payout to payout token decimals and return
        // Payout should always be positive since it is atleast 1, therefore, we can safely cast to uint256
        return (payout.intoUint256().mulDiv(baseTokenScale, uUNIT), secondsOfEmissions);
    }

    // P = (r / k) * (sqrt(2 * k * Q / p0) + k * T - 1)
    // where P is the number of payout tokens, Q is the number of quote tokens,
    // r is the emissions rate, k is the decay constant, p0 is the price target of the market,
    // and T is the time since the last auction start
    function _payoutForLinearDecay(
        uint96 lotId_,
        uint256 amount_
    ) internal view returns (uint256, uint48) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Convert to 18 decimals for fixed math by pre-computing the Q / p0 factor (which is in payout token units)
        // and then scaling using payout token decimals
        SD59x18 payout;
        uint256 baseTokenScale = 10 ** lot.baseTokenDecimals;
        {
            SD59x18 scaledQ = sd(
                int256(
                    amount_.mulDiv(10 ** lot.quoteTokenDecimals, auction.equilibriumPrice).mulDiv(
                        uUNIT, baseTokenScale
                    )
                )
            );

            // Calculate time since last auction start
            SD59x18 timeSinceLastAuctionStart =
                convert(int256(block.timestamp - uint256(auction.lastAuctionStart)));

            // Calculate factors
            SD59x18 sqrtFactor = convert(int256(2)).mul(auction.decayConstant).mul(scaledQ).sqrt();
            SD59x18 factor =
                sqrtFactor.add(auction.decayConstant.mul(timeSinceLastAuctionStart)).sub(UNIT);

            // Calculate payout
            payout = auction.emissionsRate.div(auction.decayConstant).mul(factor);
        }

        // Calculate seconds of emissions from payout or amount (depending on capacity type)
        uint48 secondsOfEmissions;
        if (lot.capacityInQuote) {
            // Convert amount to SD59x18
            SD59x18 amount = sd(int256(amount_.mulDiv(uUNIT, 10 ** lot.quoteTokenDecimals)));
            // TODO think about overflows on this cast
            secondsOfEmissions = uint48(amount.div(auction.emissionsRate).intoUint256());
        } else {
            secondsOfEmissions = uint48(payout.div(auction.emissionsRate).intoUint256());
        }

        // Scale payout to payout token decimals and return
        return (payout.intoUint256().mulDiv(baseTokenScale, uUNIT), secondsOfEmissions);
    }
}
