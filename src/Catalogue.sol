/// SPDX-License-Identifier: APGL-3.0
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";
import {FeeManager} from "src/bases/FeeManager.sol";
import {Keycode, unwrapVeecode} from "src/modules/Modules.sol";

/// @notice Contract that provides view functions for Auctions
contract Catalogue {
    address public auctionHouse;

    constructor(address auctionHouse_) {
        auctionHouse = auctionHouse_;
    }

    // ========== AUCTION INFORMATION ========== //

    function payoutFor(uint96 lotId_, uint256 amount_) external view returns (uint256) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);
        Auctioneer.Routing memory routing = Auctioneer(auctionHouse).getRouting(lotId_);

        // Calculate fees
        (Keycode auctionType,) = unwrapVeecode(routing.auctionReference);
        (uint256 protocolFee, uint256 referrerFee) =
            FeeManager(auctionHouse).calculateQuoteFees(auctionType, true, amount_); // we assume there is a referrer to give a conservative amount

        // Get payout from module
        return module.payoutFor(lotId_, amount_ - protocolFee - referrerFee);
    }

    function priceFor(uint96 lotId_, uint256 payout_) external view returns (uint256) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);
        Auctioneer.Routing memory routing = Auctioneer(auctionHouse).getRouting(lotId_);

        // Get price from module (in quote token units)
        uint256 price = module.priceFor(lotId_, payout_);

        // Calculate fee estimate assuming there is a referrer and add to price
        (Keycode auctionType,) = unwrapVeecode(routing.auctionReference);
        price += FeeManager(auctionHouse).calculateFeeEstimate(auctionType, true, price);

        return price;
    }

    function maxPayout(uint96 lotId_) external view returns (uint256) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);

        // No fees need to be considered here since an amount is not provided

        // Get max payout from module
        return module.maxPayout(lotId_);
    }

    function maxAmountAccepted(uint96 lotId_) external view returns (uint256) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);
        Auctioneer.Routing memory routing = Auctioneer(auctionHouse).getRouting(lotId_);

        // Get max amount accepted from module
        uint256 maxAmount = module.maxAmountAccepted(lotId_);

        // Calculate fee estimate assuming there is a referrer and add to max amount
        (Keycode auctionType,) = unwrapVeecode(routing.auctionReference);
        maxAmount += FeeManager(auctionHouse).calculateFeeEstimate(auctionType, true, maxAmount);

        return maxAmount;
    }

    /// @notice    Returns whether the auction is currently accepting bids or purchases
    /// @dev       Auctions that have been created, but not yet started will return false
    function isLive(uint96 lotId_) external view returns (bool) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);

        // Get isLive from module
        return module.isLive(lotId_);
    }

    function hasEnded(uint96 lotId_) external view returns (bool) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);

        // Get hasEnded from module
        return module.hasEnded(lotId_);
    }

    function remainingCapacity(uint96 lotId_) external view returns (uint256) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);

        // Get remaining capacity from module
        return module.remainingCapacity(lotId_);
    }
}
