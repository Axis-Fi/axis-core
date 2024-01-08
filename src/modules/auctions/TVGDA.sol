/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

// import "src/modules/auctions/bases/AtomicAuction.sol";
// import {SD59x18, sd, convert, uUNIT} from "prb-math/SD59x18.sol";

// /// @notice Two variable GDA. Price is dependent on time. The other variable is independent of time.
// abstract contract TVGDA {
//     /* ========== DATA STRUCTURES ========== */
//     enum Decay {
//         Linear,
//         Exponential
//     }

//     /// @notice Auction pricing data
//     struct AuctionData {
//         uint256 equilibriumPrice; // price at which the auction is balanced when emissions rate is on schedule and the independent variable is zero
//         uint256 minimumPrice; // minimum price the auction can reach
//         uint256 payoutScale;
//         uint256 quoteScale;
//         uint48 lastAuctionStart;
//         Decay priceDecayType; // type of decay to use for the market price
//         Decay variableDecayType; // type of decay to use for the independent variable
//         SD59x18 priceDecayConstant; // speed at which the price decays, as SD59x18.
//         SD59x18 variableDecayConstant; // speed at which the independent variable decays, as SD59x18.
//         SD59x18 emissionsRate; // number of tokens released per second, as SD59x18. Calculated as capacity / duration.
//     }
// }

// contract TwoVariableGradualDutchAuctioneer is AtomicAuctionModule, TVGDA {

//     /* ========== CONSTRUCTOR ========== */

//     constructor(
//         address auctionHouse_
//     ) Module(auctionHouse_) {}

//     /* ========== AUCTION FUNCTIONS ========== */

//     function _auction(
//         uint256 lotId_,
//         Lot memory lot_,
//         bytes memory params_
//     ) internal override {
//         // Decode params
//         (
//             uint256 equilibriumPrice_, // quote tokens per payout token, in quote token decimals
//             uint256 minimumPrice_, // fewest quote tokens per payout token acceptable for the auction, in quote token decimals
//             Decay priceDecayType_,
//             Decay variableDecayType_,
//             SD59x18 priceDecayConstant_,
//             SD59x18 variableDecayConstant_,
//         ) = abi.decode(params_, (uint256, uint256, Decay, Decay, SD59x18, SD59x18));

//         // Validate params
//         // TODO

//         // Calculate scale from payout token decimals
//         uint256 payoutScale = 10 ** uint256(lot_.payoutToken.decimals());
//         uint256 quoteScale = 10 ** uint256(lot_.quoteToken.decimals());

//         // Calculate emissions rate
//         uint256 payoutCapacity = lot_.capacityInQuote ? lot_.capacity.mulDiv(payoutScale, equilibriumPrice_) : lot_.capacity;
//         SD59x18 emissionsRate = sd(int256(payoutCapacity.mulDiv(uUNIT, (lot_.conclusion - lot_.start) * payoutScale)));

//         // Set auction data
//         AuctionData storage auction = auctionData[lotId_];
//         auction.equilibriumPrice = equilibriumPrice_;
//         auction.minimumPrice = minimumPrice_;
//         auction.payoutScale = payoutScale;
//         auction.quoteScale = quoteScale;
//         auction.lastAuctionStart = uint48(block.timestamp);
//         auction.priceDecayType = priceDecayType_;
//         auction.variableDecayType = variableDecayType_;
//         auction.priceDecayConstant = priceDecayConstant_;
//         auction.variableDecayConstant = variableDecayConstant_;
//         auction.emissionsRate = emissionsRate;
//     }

//     function _purchase(uint256 lotId_, uint256 amount_, bytes memory variableInput_) internal override returns (uint256) {
//         // variableInput should be a single uint256
//         uint256 variableInput = abi.decode(variableInput_, (uint256));

//         // Calculate payout amount for quote amount and seconds of emissions using GDA formula
//         (uint256 payout, uint48 secondsOfEmissions) = _payoutAndEmissionsFor(id_, amount_, variableInput);

//         // Update last auction start with seconds of emissions
//         // Do not have to check that too many seconds have passed here
//         // since payout/amount is checked against capacity in the top-level function
//         auctionData[id_].lastAuctionStart += secondsOfEmissions;

//         return payout;
//     }

//     function _payoutAndEmissionsFor(uint256 lotId_, uint256 amount_, uint256 variableInput_) internal view override returns (uint256) {
//         // Load decay types for lot
//         priceDecayType = auctionData[lotId_].priceDecayType;
//         variableDecayType = auctionData[lotId_].variableDecayType;

//         // Get payout information based on the various combinations of decay types
//         if (priceDecayType == Decay.Linear && variableDecayType == Decay.Linear) {
//             return _payoutForLinLin(auction, amount_, variableInput_);
//         } else if (priceDecayType == Decay.Linear && variableDecayType == Decay.Exponential) {
//             return _payoutForLinExp(auction, amount_, variableInput_);
//         } else if (priceDecayType == Decay.Exponential && variableDecayType == Decay.Linear) {
//             return _payoutForExpLin(auction, amount_, variableInput_);
//         } else {
//             return _payoutForExpExp(auction, amount_, variableInput_);
//         }
//     }

//     // TODO problem with having a minimum price -> messes up the math and the inverse solution is not closed form
//     function _payoutForExpExp(
//         uint256 lotId_,
//         uint256 amount_,
//         uint256 variableInput_
//     ) internal view returns (uint256, uint48) {

//     }
// }
