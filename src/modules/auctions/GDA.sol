// /// SPDX-License-Identifier: AGPL-3.0
// pragma solidity 0.8.19;

// import "src/modules/auctions/bases/AtomicAuction.sol";
// import {SD59x18, sd, convert, uUNIT} from "prb-math/SD59x18.sol";

// abstract contract GDA {
//     /* ========== DATA STRUCTURES ========== */
//     enum Decay {
//         Linear,
//         Exponential
//     }

//     /// @notice Auction pricing data
//     struct AuctionData {
//         uint256 equilibriumPrice; // price at which the auction is balanced
//         uint256 minimumPrice; // minimum price the auction can reach
//         uint256 baseScale;
//         uint256 quoteScale;
//         uint48 lastAuctionStart;
//         Decay decayType; // type of decay to use for the market
//         SD59x18 decayConstant; // speed at which the price decays, as SD59x18.
//         SD59x18 emissionsRate; // number of tokens released per second, as SD59x18. Calculated as capacity / duration.
//     }

//     /* ========== STATE ========== */

//     SD59x18 public constant ONE = SD59x18.wrap(1e18);
//     mapping(uint256 lotId => AuctionData) public auctionData;
// }

// contract GradualDutchAuctioneer is AtomicAuctionModule, GDA {
//     /* ========== ERRORS ========== */
//     error InsufficientCapacity();
//     error InvalidParams();

//     /* ========== CONSTRUCTOR ========== */

//     constructor(
//         address auctionHouse_
//     ) Module(auctionHouse_) {}

//     /* ========== MODULE FUNCTIONS ========== */
//     function ID() public pure override returns (Keycode, uint8) {
//         return (toKeycode("GDA"), 1);
//     }

//     /* ========== MARKET FUNCTIONS ========== */

//     function _auction(
//         uint256 id_,
//         Lot memory lot_,
//         bytes memory params_
//     ) internal override {
//         // Decode params
//         (
//             uint256 equilibriumPrice_, // quote tokens per base token, so would be in quote token decimals?
//             Decay decayType_,
//             SD59x18 decayConstant_
//         ) = abi.decode(params_, (uint256, Decay, SD59x18));

//         // Validate params
//         // TODO

//         // Calculate scale from base token decimals
//         uint256 baseScale = 10 ** uint256(lot_.baseToken.decimals());
//         uint256 quoteScale = 10 ** uint256(lot_.quoteToken.decimals());

        
//         // Calculate emissions rate        
//         uint256 baseCapacity = lot_.capacityInQuote ? lot_.capacity.mulDiv(baseScale, equilibriumPrice_) : lot_.capacity;
//         SD59x18 emissionsRate = sd(int256(baseCapacity.mulDiv(uUNIT, (lot_.conclusion - lot_.start) * baseScale)));

//         // Set auction data
//         AuctionData storage auction = auctionData[id_];
//         auction.equilibriumPrice = equilibriumPrice_;
//         auction.baseScale = baseScale;
//         auction.quoteScale = quoteScale;
//         auction.lastAuctionStart = uint48(block.timestamp);
//         auction.decayType = decayType_;
//         auction.decayConstant = decayConstant_;
//         auction.emissionsRate = emissionsRate;
//     }

//     /* ========== TELLER FUNCTIONS ========== */

//     function _purchase(uint256 id_, uint256 amount_) internal override returns (uint256) {
//         // Calculate payout amount for quote amount and seconds of emissions using GDA formula
//         (uint256 payout, uint48 secondsOfEmissions) = _payoutAndEmissionsFor(id_, amount_);

//         // Update last auction start with seconds of emissions
//         // Do not have to check that too many seconds have passed here
//         // since payout/amount is checked against capacity in the top-level function
//         auctionData[id_].lastAuctionStart += secondsOfEmissions;

//         return payout;
//     }

//     /* ========== PRICE FUNCTIONS ========== */

//     function priceFor(uint256 id_, uint256 payout_) public view override returns (uint256) {
//         Decay decayType = auctionData[id_].decayType;

//         uint256 amount;
//         if (decayType == Decay.EXPONENTIAL) {
//             amount = _exponentialPriceFor(id_, payout_);
//         } else if (decayType == Decay.LINEAR) {
//             amount = _linearPriceFor(id_, payout_);
//         }

//         // Check that amount in or payout do not exceed remaining capacity
//         Lot memory lot = lotData[id_];
//         if (lot.capacityInQuote ? amount > lot.capacity : payout_ > lot.capacity)
//             revert InsufficientCapacity();

//         return amount;
//     }

//     // For Continuos GDAs with exponential decay, the price of a given token t seconds after being emitted is: p(t) = p0 * e^(-k*t)
//     // Integrating this function from the last auction start time for a particular number of tokens, gives the multiplier for the token price to determine amount of quote tokens required to purchase
//     // P(T) = (p0 / k) * (e^(k*q/r) - 1) / e^(k*T) where T is the time since the last auction start, q is the number of tokens to purchase, p0 is the initial price, and r is the emissions rate
//     function _exponentialPriceFor(uint256 id_, uint256 payout_) internal view returns (uint256) {
//         Lot memory lot = lotData[id_];
//         AuctionData memory auction = auctionData[id_];

//         // Convert payout to SD59x18. We scale first to 18 decimals from the base token decimals
//         SD59x18 payout = sd(int256(payout_.mulDiv(uUNIT, auction.baseScale)));

//         // Calculate time since last auction start
//         SD59x18 timeSinceLastAuctionStart = convert(
//             int256(block.timestamp - uint256(auction.lastAuctionStart))
//         );

//         // Calculate the first numerator factor
//         SD59x18 num1 = sd(int256(auction.equilibriumPrice.mulDiv(uUNIT, auction.quoteScale))).div(
//             auction.decayConstant
//         );

//         // Calculate the second numerator factor
//         SD59x18 num2 = auction.decayConstant.mul(payout).div(auction.emissionsRate).exp().sub(ONE);

//         // Calculate the denominator
//         SD59x18 denominator = auction.decayConstant.mul(timeSinceLastAuctionStart).exp();

//         // Calculate return value
//         // This value should always be positive, therefore, we can safely cast to uint256
//         // We scale the return value back to base token decimals
//         return num1.mul(num2).div(denominator).intoUint256().mulDiv(auction.quoteScale, uUNIT);
//     }

//     // p(t) = p0 * (1 - k*t) where p0 is the initial price, k is the decay constant, and t is the time since the last auction start
//     // P(T) = (p0 * q / r) * (1 - k*T + k*q/2r) where T is the time since the last auction start, q is the number of tokens to purchase,
//     // r is the emissions rate, and p0 is the initial price
//     function _linearPriceFor(uint256 id_, uint256 payout_) internal view returns (uint256) {
//         Lot memory lot = lotData[id_];
//         AuctionData memory auction = auctionData[id_];

//         // Convert payout to SD59x18. We scale first to 18 decimals from the base token decimals
//         SD59x18 payout = sd(int256(payout_.mulDiv(uUNIT, auction.baseScale)));

//         // Calculate time since last auction start
//         SD59x18 timeSinceLastAuctionStart = convert(
//             int256(block.timestamp - uint256(auction.lastAuctionStart))
//         );

//         // Calculate decay factor
//         // TODO can we confirm this will be positive?
//         SD59x18 decayFactor = ONE.sub(auction.decayConstant.mul(timeSinceLastAuctionStart)).add(
//             auction.decayConstant.mul(payout).div(convert(int256(2)).mul(auction.emissionsRate))
//         );

//         // Calculate payout factor
//         SD59x18 payoutFactor = payout.mul(
//             sd(int256(auction.equilibriumPrice.mulDiv(uUNIT, auction.quoteScale)))
//         ).div(auction.emissionsRate); // TODO do we lose precision here by dividing early?

//         // Calculate final return value and convert back to market scale
//         return
//             payoutFactor.mul(decayFactor).intoUint256().mulDiv(
//                 auction.quoteScale,
//                 uUNIT
//             );
//     }

//     /* ========== PAYOUT CALCULATIONS ========== */

//     function _payoutFor(uint256 id_, uint256 amount_) internal view returns (uint256) {
//         (uint256 payout, ) = _payoutAndEmissionsFor(id_, amount_);

//         // Check that amount in or payout do not exceed remaining capacity
//         Lot memory lot = lotData[id_];
//         if (lot.capacityInQuote ? amount_ > lot.capacity : payout > lot.capacity)
//             revert InsufficientCapacity();

//         return payout;
//     }

//     function _payoutAndEmissionsFor(
//         uint256 id_,
//         uint256 amount_
//     ) internal view returns (uint256, uint48) {
//         Decay decayType = auctionData[id_].decayType;

//         if (decayType == Decay.EXPONENTIAL) {
//             return _payoutForExpDecay(id_, amount_);
//         } else if (decayType == Decay.LINEAR) {
//             return _payoutForLinearDecay(id_, amount_);
//         } else {
//             revert InvalidParams();
//         }
//     }

//     // TODO check this math again
//     // P = (r / k) * ln(Q * k / p0 * e^(k*T) + 1) where P is the number of base tokens, Q is the number of quote tokens, r is the emissions rate, k is the decay constant,
//     // p0 is the price target of the market, and T is the time since the last auction start
//     function _payoutForExpDecay(
//         uint256 id_,
//         uint256 amount_
//     ) internal view returns (uint256, uint48) {
//         AuctionData memory auction = auctionData[id_];

//         // Convert to 18 decimals for fixed math by pre-computing the Q / p0 factor 
//         SD59x18 scaledQ = sd(
//             int256(
//                 amount_.mulDiv(auction.uUNIT, auction.equilibriumPrice)
//             )
//         );

//         // Calculate time since last auction start
//         SD59x18 timeSinceLastAuctionStart = convert(
//             int256(block.timestamp - uint256(auction.lastAuctionStart))
//         );

//         // Calculate the logarithm
//         SD59x18 logFactor = auction
//             .decayConstant
//             .mul(timeSinceLastAuctionStart)
//             .exp()
//             .mul(scaledQ)
//             .mul(auction.decayConstant)
//             .add(ONE)
//             .ln();

//         // Calculate the payout
//         SD59x18 payout = logFactor.mul(auction.emissionsRate).div(auction.decayConstant);

//         // Scale back to base token decimals
//         // TODO verify we can safely cast to uint256
//         return payout.intoUint256().mulDiv(auction.baseScale, uUNIT);

//         // Calculate seconds of emissions from payout or amount (depending on capacity type)
//         // TODO emissionsRate is being set only in base tokens over, need to think about this
//         // Might just use equilibrium price to convert the quote amount here to payout amount and then divide by emissions rate
//         uint48 secondsOfEmissions;
//         if (lotData[id_].capacityInQuote) {
//             // Convert amount to SD59x18
//             SD59x18 amount = sd(int256(amount_.mulDiv(uUNIT, auction.quoteScale)));
//             secondsOfEmissions = uint48(amount.div(auction.emissionsRate).intoUint256());
//         } else {
//             secondsOfEmissions = uint48(payout.div(auction.emissionsRate).intoUint256());
//         }

//         // Scale payout to base token decimals and return
//         // Payout should always be positive since it is atleast 1, therefore, we can safely cast to uint256
//         return (payout.intoUint256().mulDiv(auction.baseScale, uUNIT), secondsOfEmissions);
//     }

//     // TODO check this math again
//     // P = (r / k) * (sqrt(2 * k * Q / p0) + k * T - 1) where P is the number of base tokens, Q is the number of quote tokens, r is the emissions rate, k is the decay constant,
//     // p0 is the price target of the market, and T is the time since the last auction start
//     function _payoutForLinearDecay(uint256 id_, uint256 amount_) internal view returns (uint256) {
//         AuctionData memory auction = auctionData[id_];

//         // Convert to 18 decimals for fixed math by pre-computing the Q / p0 factor 
//         SD59x18 scaledQ = sd(
//             int256(amount_.mulDiv(uUNIT, auction.equilibriumPrice))
//         );

//         // Calculate time since last auction start
//         SD59x18 timeSinceLastAuctionStart = convert(
//             int256(block.timestamp - uint256(auction.lastAuctionStart))
//         );

//         // Calculate factors
//         SD59x18 sqrtFactor = convert(int256(2)).mul(auction.decayConstant).mul(scaledQ).sqrt();
//         SD59x18 factor = sqrtFactor.add(auction.decayConstant.mul(timeSinceLastAuctionStart)).sub(
//             ONE
//         );

//         // Calculate payout
//         SD59x18 payout = auction.emissionsRate.div(auction.decayConstant).mul(factor);

//         // Calculate seconds of emissions from payout or amount (depending on capacity type)
//         // TODO same as in the above function
//         uint48 secondsOfEmissions;
//         if (lotData[id_].capacityInQuote) {
//             // Convert amount to SD59x18
//             SD59x18 amount = sd(int256(amount_.mulDiv(uUNIT, auction.scale)));
//             secondsOfEmissions = uint48(amount.div(auction.emissionsRate).intoUint256());
//         } else {
//             secondsOfEmissions = uint48(payout.div(auction.emissionsRate).intoUint256());
//         }

//         // Scale payout to base token decimals and return
//         return (payout.intoUint256().mulDiv(auction.baseScale, uUNIT), secondsOfEmissions);
//     }
//     /* ========== ADMIN FUNCTIONS ========== */
//     /* ========== VIEW FUNCTIONS ========== */
// }
