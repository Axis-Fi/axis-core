/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// Protocol dependencies
import {AtomicAuctionModule} from "src/modules/auctions/bases/AtomicAuctionModule.sol";

// Libraries
import {SD59x18, sd, convert, ZERO, UNIT} from "lib/prb-math/src/SD59x18.sol";
import {FullMath} from "src/lib/FullMath.sol";

// TODO can probably switch from signed math to unsigned math, but need to research it a bit more.
// There are also some assumptions that need to hold for the square roots to be valid and those need to be documented and validated.

contract GradualDutchAuction is AtomicAuctionModule {
    using FullMath for uint256;

    // ========== DATA STRUCTURES ========== //

    enum Decay {
        Linear,
        Exponential
    }

    /// @notice Auction pricing data
    struct AuctionData {
        uint256 equilibriumPrice; // price at which the auction is balanced
        uint256 minimumPrice; // minimum price for the auction
        uint48 lastAuctionStart;
        Decay decayType; // type of decay to use for the market
        SD59x18 decayConstant; // speed at which the price decays, as SD59x18.
        SD59x18 emissionsRate; // number of tokens released per second, as SD59x18. Calculated as capacity / duration.
    }

    struct GDAParams {
        uint256 equilibriumPrice;
        uint256 minimumPrice;
        SD59x18 decayConstant;
        Decay decayType;
    }

    // ========== STATE VARIABLES ========== //

    SD59x18 internal constant _TWO = SD59x18.wrap(int256(2e18));
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
        // Equilibrium Price must not be zero and greater than minimum price (which can be zero)
        if (params.equilibriumPrice == 0 || params.equilibriumPrice <= params.minimumPrice) {
            revert Auction_InvalidParams();
        }

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
        SD59x18 emissionsRate = sd(
            int256(uint256(lot_.capacity).mulDiv(_uUNIT, 10 ** lot_.baseTokenDecimals))
        ).div(duration);

        // Store auction data
        AuctionData storage data = auctionData[lotId_];
        data.equilibriumPrice = params.equilibriumPrice;
        data.minimumPrice = params.minimumPrice;
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
    // q(t) = q0 * e^(-k*t)
    // where k is the decay constant and q0 is the initial price
    // Integrating this function from the last auction start time for a particular number of tokens,
    // gives the multiplier for the token price to determine amount of quote tokens required to purchase:
    // Q(T) = (q0 * (e^(k*P) - 1)) / ke^(k*T)
    // where T is the time since the last auction start, P is the number of tokens to purchase.
    // If the price is less than the minimum price for the provided payout value, then the minimum is returned
    function _exponentialPriceFor(uint96 lotId_, uint256 payout_) internal view returns (uint256) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Convert payout to SD59x18. We scale first to 18 decimals from the payout token decimals
        uint256 baseTokenScale = 10 ** lot.baseTokenDecimals;
        SD59x18 payout = sd(int256(payout_.mulDiv(_uUNIT, baseTokenScale)));

        // Calculate time since last auction start
        SD59x18 timeSinceLastAuctionStart =
            convert(int256(block.timestamp - uint256(auction.lastAuctionStart)));

        // Scale the initial price to 18 decimals, set as numerator factor 1
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        SD59x18 num1 = sd(int256(auction.equilibriumPrice.mulDiv(_uUNIT, quoteTokenScale)));

        // Calculate the second numerator factor
        SD59x18 num2 = auction.decayConstant.mul(payout).exp().sub(UNIT);

        // Calculate the denominator
        SD59x18 denominator =
            auction.decayConstant.mul(timeSinceLastAuctionStart).exp().mul(auction.decayConstant);

        // Calculate auction price
        // This value should always be positive, therefore, we can safely cast to uint256
        // We scale the price back to quote token decimals
        uint256 price =
            num1.mul(num2).div(denominator).intoUint256().mulDiv(quoteTokenScale, _uUNIT);

        // Calculate the minimum price for the payout amount
        uint256 minPrice = auction.minimumPrice.mulDiv(payout_, baseTokenScale);

        // Return the maximum of the price and the minimum price
        return price > minPrice ? price : minPrice;
    }

    // q(t) = (q0 - qMin) * (1 - k*t) + qMin
    // where q0 is the initial price, qMin is the minimum price,
    // k is the decay constant, and t is the time since the last auction start
    // Q(T) = (k * (q0 - qMin) * (P^2 / r^2 - 2 * T * P / r) / 2) + (q0 * P) / r
    // where T is the time since the last auction start, q is the number of tokens to purchase,
    // r is the emissions rate, and p0 is the initial price
    function _linearPriceFor(uint96 lotId_, uint256 payout_) internal view returns (uint256) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Convert payout to SD59x18. We scale first to 18 decimals from the payout token decimals
        uint256 baseTokenScale = 10 ** lot.baseTokenDecimals;
        SD59x18 payout = sd(int256(payout_.mulDiv(_uUNIT, baseTokenScale)));

        // Calculate the payout factor: (P^2 / r^2 - 2 * T * P / r)
        SD59x18 payoutFactor;
        {
            // Caclualate the first factor: P^2 / r^2
            SD59x18 f1 = payout.mul(payout).div(auction.emissionsRate.mul(auction.emissionsRate));

            // Calculate time since last auction start
            SD59x18 timeSinceLastAuctionStart =
                convert(int256(block.timestamp - uint256(auction.lastAuctionStart)));

            // Calculate the second factor: 2 * T * P / r
            SD59x18 f2 = timeSinceLastAuctionStart.mul(payout).mul(_TWO).div(auction.emissionsRate);

            // Combine
            payoutFactor = f1.sub(f2);
        }

        // Convert the equilibrium and minimum prices to 18 decimals
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        SD59x18 q0 = sd(int256(auction.equilibriumPrice.mulDiv(_uUNIT, quoteTokenScale)));
        SD59x18 qMin = sd(int256(auction.minimumPrice.mulDiv(_uUNIT, quoteTokenScale)));

        // Calculate the first factor: (k * (q0 - qMin) * payoutFactor / 2)
        SD59x18 firstFactor = auction.decayConstant.mul(q0.sub(qMin)).mul(payoutFactor).div(_TWO);

        // Calculate the second factor: (q0 * payout / r)
        SD59x18 secondFactor = q0.mul(payout).div(auction.emissionsRate);

        // Calculate the price, convert back to quote token scale
        return firstFactor.add(secondFactor).intoUint256().mulDiv(quoteTokenScale, _uUNIT);
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

    // P = (r * ln((Q * k * e^(k*T) / k) + 1)) / q0
    // where P is the number of payout tokens, Q is the number of quote tokens,
    // r is the emissions rate, k is the decay constant, q0 is the equilibrium price of the auction,
    // and T is the time since the last auction start
    function _payoutForExpDecay(
        uint96 lotId_,
        uint256 amount_
    ) internal view returns (uint256, uint48) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Factors are calculated in a certain order to avoid precision loss

        // Get quote token scale and convert equilibrium price to 18 decimals
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        SD59x18 q0 = sd(int256(auction.equilibriumPrice.mulDiv(_uUNIT, quoteTokenScale)));

        // Scale amount to 18 decimals
        SD59x18 amount = sd(int256(amount_.mulDiv(_uUNIT, quoteTokenScale)));

        // Calculate the logarithm factor
        SD59x18 logFactor;
        {
            // Calculate the exponential factor
            SD59x18 ekt = auction.decayConstant.mul(
                convert(int256(block.timestamp - uint256(auction.lastAuctionStart)))
            ).exp();

            // Calculate the logarithm
            logFactor = amount.mul(auction.decayConstant).mul(ekt).div(q0).add(UNIT).ln();
        }

        // Calculate the payout
        SD59x18 payout = auction.emissionsRate.mul(logFactor).div(auction.decayConstant);

        // Calculate the payout at the minimum price for the provided amount of quote tokens
        SD59x18 minimumPrice = sd(int256(auction.minimumPrice.mulDiv(_uUNIT, quoteTokenScale)));
        SD59x18 maxPayout = amount.div(minimumPrice);

        // Set the payout as the minimum of the calculated payout and the maximum payout
        payout = payout < maxPayout ? payout : maxPayout;

        // Calculate seconds of emissions from payout or amount (depending on capacity type)
        uint48 secondsOfEmissions;
        if (lot.capacityInQuote) {
            // TODO need to think about overflows on this cast
            secondsOfEmissions = uint48(amount.div(auction.emissionsRate).intoUint256());
        } else {
            secondsOfEmissions = uint48(payout.div(auction.emissionsRate).intoUint256());
        }

        // Scale payout to payout token decimals and return
        // Payout should always be positive since it is atleast 1, therefore, we can safely cast to uint256
        return
            (payout.intoUint256().mulDiv(10 ** lot.baseTokenDecimals, _uUNIT), secondsOfEmissions);
    }

    // P = (2 * r * (sqrt(Q + ((q0 - k * T * (q0 - qMin))^2) - ((q0 - k * T * (q0 - qMin))))) / sqrt(2 * k * (q0 - qMin))
    // where P is the number of payout tokens, Q is the number of quote tokens,
    // r is the emissions rate, k is the decay constant, p0 is the price target of the auction,
    // qMin is the minimum price of the auction, and T is the time since the last auction start
    function _payoutForLinearDecay(
        uint96 lotId_,
        uint256 amount_
    ) internal view returns (uint256, uint48) {
        Lot memory lot = lotData[lotId_];
        AuctionData memory auction = auctionData[lotId_];

        // Calculate the largest factor first
        // Steps are structured to avoid precision loss from early divisions where possible

        // Convert the amount to 18 decimals
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        SD59x18 amount = sd(int256(amount_.mulDiv(_uUNIT, quoteTokenScale)));

        // Convert the price values to 18 decimals
        SD59x18 q0 = sd(int256(auction.equilibriumPrice.mulDiv(_uUNIT, quoteTokenScale)));
        SD59x18 qMin = sd(int256(auction.minimumPrice.mulDiv(_uUNIT, quoteTokenScale)));

        // There are some expressions that are used several times
        // We pre-calculate these to save gas
        // 2 * k * (q0 - qMin)
        SD59x18 twoKQDiff = auction.decayConstant.mul(q0.sub(qMin)).mul(_TWO);
        // k * T * (q0 - qMin)
        SD59x18 kTQDiff = auction.decayConstant.mul(
            convert(int256(block.timestamp - uint256(auction.lastAuctionStart))).mul(q0.sub(qMin))
        );

        // Calculate the numerator
        SD59x18 num;
        {
            // Calculate the first num factor (sqrt(Q + ((q0 - k * T * (q0 - qMin))^2)))
            SD59x18 f1 = amount.mul(twoKQDiff).add(kTQDiff.mul(kTQDiff)).sqrt();

            // Calculate the second num factor
            SD59x18 f2 = q0.sub(kTQDiff);

            // Combine the numerator factors and multiply by 2 * r
            num = f1.sub(f2).mul(_TWO).mul(auction.emissionsRate);
        }

        // Calculate the denominator
        SD59x18 den = twoKQDiff.sqrt();

        // Calculate the payout
        SD59x18 payout = num.div(den);

        // Calculate seconds of emissions from payout or amount (depending on capacity type)
        uint48 secondsOfEmissions;
        if (lot.capacityInQuote) {
            // TODO think about overflows on this cast
            secondsOfEmissions = uint48(amount.div(auction.emissionsRate).intoUint256());
        } else {
            secondsOfEmissions = uint48(payout.div(auction.emissionsRate).intoUint256());
        }

        // Scale payout to payout token decimals and return
        return
            (payout.intoUint256().mulDiv(10 ** lot.baseTokenDecimals, _uUNIT), secondsOfEmissions);
    }
}
