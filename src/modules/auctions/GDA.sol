// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IAtomicAuction} from "src/interfaces/IAtomicAuction.sol";

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
        UD60x18 decayConstant;
    }

    // ========== STATE VARIABLES ========== //

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

        // Validate the decay constant
        // Cannot be zero
        // TODO do we need to set tighter bounds on this?
        if (params.decayConstant == ZERO) revert Auction_InvalidParams();

        // TODO other validation checks?

        // Calculate emissions rate
        UD60x18 duration = convert(uint256(lot_.conclusion - lot_.start));
        UD60x18 emissionsRate =
            ud(lot_.capacity.fullMulDiv(uUNIT, 10 ** lot_.baseTokenDecimals)).div(duration);

        // Store auction data
        AuctionData storage data = auctionData[lotId_];
        data.equilibriumPrice = params.equilibriumPrice;
        data.minimumPrice = params.minimumPrice;
        data.decayConstant = params.decayConstant;
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

        // Calculate time since last auction start
        // TODO handle case where lastAuctionStart is greater than block.timestamp
        UD60x18 timeSinceLastAuctionStart =
            convert(block.timestamp - uint256(auction.lastAuctionStart));

        // Subtract the minimum price from the equilibrium price
        // In the auction creation, we checked that the equilibrium price is greater than the minimum price
        // Scale the result to 18 decimals, set as numerator factor 1
        uint256 quoteTokenScale = 10 ** lot.quoteTokenDecimals;
        UD60x18 num1 =
            ud((auction.equilibriumPrice - auction.minimumPrice).fullMulDiv(uUNIT, quoteTokenScale));

        // Calculate the second numerator factor: e^((k*P)/r) - 1
        UD60x18 num2 = auction.decayConstant.mul(payout).div(auction.emissionsRate).exp().sub(UNIT);

        // Calculate the denominator: ke^(k*T)
        UD60x18 denominator =
            auction.decayConstant.mul(timeSinceLastAuctionStart).exp().mul(auction.decayConstant);

        // Calculate first term
        UD60x18 result = num1.mul(num2).div(denominator);

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
            // Calculate the exponential factor
            // TODO lastAuctionStart may be greater than block.timestamp if the auction is ahead of schedule
            // Need to handle this case
            UD60x18 ekt =
                auction.decayConstant.mul(convert(block.timestamp - auction.lastAuctionStart)).exp();

            // Calculate the logarithm
            // Operand is guaranteed to be >= 1, so the result is positive
            UD60x18 logFactor = amount.mul(auction.decayConstant).mul(ekt).div(q0).add(UNIT).ln();

            // Calculate the payout
            payout = auction.emissionsRate.mul(logFactor).div(auction.decayConstant);
        } else {
            // TODO think about refactoring to avoid precision loss

            // TODO do we check if amount divided by minimum price is greater than capacity?
            // May help with some overflow situations below.

            // Convert minimum price to 18 decimals
            UD60x18 qm = ud(auction.minimumPrice.mulDiv(uUNIT, quoteTokenScale));

            // Calculate first term:  (k * Q) / qm
            UD60x18 f = auction.decayConstant.mul(amount).div(qm);

            // Calculate second term aka C: (q0 - qm)/(qm * e^(k * T))
            // TODO lastAuctionStart may be greater than block.timestamp if the auction is ahead of schedule
            // Need to handle this case
            UD60x18 c = q0.sub(qm).div(
                auction.decayConstant.mul(convert(block.timestamp - auction.lastAuctionStart)).exp()
                    .mul(qm)
            );

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

    function maxPayout(uint96 lotId_) external view override returns (uint256) {
        // The max payout is the remaining capacity of the lot
        return lotData[lotId_].capacity;
    }

    function maxAmountAccepted(uint96 lotId_) external view override returns (uint256) {
        // The max amount accepted is the price to purchase the remaining capacity of the lot
        return priceFor(lotId_, lotData[lotId_].capacity);
    }
}