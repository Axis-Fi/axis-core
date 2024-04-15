// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {Catalogue} from "src/bases/Catalogue.sol";
import {AtomicAuction} from "src/modules/auctions/AtomicAuctionModule.sol";
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {FeeManager} from "src/bases/FeeManager.sol";
import {keycodeFromVeecode, Keycode} from "src/modules/Modules.sol";

/// @notice Contract that provides view functions for atomic auctions
contract AtomicCatalogue is Catalogue {
    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_) Catalogue(auctionHouse_) {}

    // ========== ATOMIC AUCTION ========== //

    /// @notice     Returns the payout for a given lot and amount
    function payoutFor(uint96 lotId_, uint256 amount_) external view returns (uint256) {
        AtomicAuction module =
            AtomicAuction(address(AuctionHouse(auctionHouse).getModuleForId(lotId_)));
        AuctionHouse.Routing memory routing = getRouting(lotId_);

        // Get protocol fee from FeeManager
        (uint48 protocolFee, uint48 referrerFee,) =
            FeeManager(auctionHouse).fees(keycodeFromVeecode(routing.auctionReference));

        // Calculate fees
        (uint256 toProtocol, uint256 toReferrer) =
            FeeManager(auctionHouse).calculateQuoteFees(protocolFee, referrerFee, true, amount_);

        // Get payout from module
        return module.payoutFor(lotId_, amount_ - uint96(toProtocol) - uint96(toReferrer));
    }

    /// @notice     Returns the price for a given lot and payout
    function priceFor(uint96 lotId_, uint256 payout_) external view returns (uint256) {
        AtomicAuction module =
            AtomicAuction(address(AuctionHouse(auctionHouse).getModuleForId(lotId_)));
        AuctionHouse.Routing memory routing = getRouting(lotId_);

        // Get price from module (in quote token units)
        uint256 price = module.priceFor(lotId_, payout_);

        // Calculate fee estimate assuming there is a referrer and add to price
        price += _calculateFeeEstimate(keycodeFromVeecode(routing.auctionReference), price);

        return price;
    }

    /// @notice     Returns the max payout for a given lot
    function maxPayout(uint96 lotId_) external view returns (uint256) {
        AtomicAuction module =
            AtomicAuction(address(AuctionHouse(auctionHouse).getModuleForId(lotId_)));

        // No fees need to be considered here since an amount is not provided

        // Get max payout from module
        return module.maxPayout(lotId_);
    }

    /// @notice     Returns the max amount accepted for a given lot
    function maxAmountAccepted(uint96 lotId_) external view returns (uint256) {
        AtomicAuction module =
            AtomicAuction(address(AuctionHouse(auctionHouse).getModuleForId(lotId_)));
        AuctionHouse.Routing memory routing = getRouting(lotId_);

        // Get max amount accepted from module
        uint256 maxAmount = module.maxAmountAccepted(lotId_);

        // Calculate fee estimate assuming there is a referrer and add to max amount
        maxAmount += _calculateFeeEstimate(keycodeFromVeecode(routing.auctionReference), maxAmount);

        return maxAmount;
    }

    // ========== INTERNAL UTILITY FUNCTIONS ========== //

    /// @notice Estimates fees for a `priceFor` or `maxAmountAccepted` calls
    function _calculateFeeEstimate(
        Keycode auctionType_,
        uint256 price_
    ) internal view returns (uint256 feeEstimate) {
        // In this case we have to invert the fee calculation
        // We provide a conservative estimate by assuming there is a referrer and rounding up
        (uint48 fee, uint48 referrerFee,) = FeeManager(auctionHouse).fees(auctionType_);
        fee += referrerFee;

        uint256 numer = price_ * _FEE_DECIMALS;
        uint256 denom = _FEE_DECIMALS - fee;

        return (numer / denom) + ((numer % denom == 0) ? 0 : 1); // round up if necessary
    }
}
