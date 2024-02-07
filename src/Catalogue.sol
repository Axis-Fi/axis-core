/// SPDX-License-Identifier: APGL-3.0
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";
import {FeeManager} from "src/bases/FeeManager.sol";
import {Veecode, keycodeFromVeecode, Keycode} from "src/modules/Modules.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";

/// @notice Contract that provides view functions for Auctions
contract Catalogue {
    // ========== STATE VARIABLES ========== //
    /// @notice Address of the AuctionHouse contract
    address public auctionHouse;

    /// @notice     Fees are in basis points (3 decimals). 1% equals 1000.
    uint48 internal constant _FEE_DECIMALS = 1e5;

    constructor(address auctionHouse_) {
        auctionHouse = auctionHouse_;
    }

    // ========== AUCTION INFORMATION ========== //

    /// @notice     Gets the routing information for a given lot ID
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///
    /// @param      lotId_  ID of the auction lot
    /// @return     routing Routing information for the auction lot
    function getRouting(uint96 lotId_) public view returns (Auctioneer.Routing memory) {
        (
            Veecode auctionReference,
            address owner,
            ERC20 baseToken,
            ERC20 quoteToken,
            IHooks hooks,
            IAllowlist allowlist,
            Veecode derivativeReference,
            bytes memory derivativeParams,
            bool wrapDerivative,
            uint256 prefunding
        ) = Auctioneer(msg.sender).lotRouting(lotId_);

        return Auctioneer.Routing({
            auctionReference: auctionReference,
            owner: owner,
            baseToken: baseToken,
            quoteToken: quoteToken,
            hooks: hooks,
            allowlist: allowlist,
            derivativeReference: derivativeReference,
            derivativeParams: derivativeParams,
            wrapDerivative: wrapDerivative,
            prefunding: prefunding
        });
    }

    function payoutFor(uint96 lotId_, uint256 amount_) external view returns (uint256) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);
        Auctioneer.Routing memory routing = getRouting(lotId_);

        // Calculate fees
        (uint256 protocolFee, uint256 referrerFee) = FeeManager(auctionHouse).calculateQuoteFees(
            keycodeFromVeecode(routing.auctionReference), true, amount_
        ); // we assume there is a referrer to give a conservative amount

        // Get payout from module
        return module.payoutFor(lotId_, amount_ - protocolFee - referrerFee);
    }

    function priceFor(uint96 lotId_, uint256 payout_) external view returns (uint256) {
        Auction module = Auctioneer(auctionHouse).getModuleForId(lotId_);
        Auctioneer.Routing memory routing = getRouting(lotId_);

        // Get price from module (in quote token units)
        uint256 price = module.priceFor(lotId_, payout_);

        // Calculate fee estimate assuming there is a referrer and add to price
        price += _calculateFeeEstimate(keycodeFromVeecode(routing.auctionReference), true, price);

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
        Auctioneer.Routing memory routing = getRouting(lotId_);

        // Get max amount accepted from module
        uint256 maxAmount = module.maxAmountAccepted(lotId_);

        // Calculate fee estimate assuming there is a referrer and add to max amount
        maxAmount +=
            _calculateFeeEstimate(keycodeFromVeecode(routing.auctionReference), true, maxAmount);

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

    // ========== INTERNAL UTILITY FUNCTIONS ========== //

    /// @notice Estimates fees for a `priceFor` or `maxAmountAccepted` calls
    function _calculateFeeEstimate(
        Keycode auctionType_,
        bool hasReferrer_,
        uint256 price_
    ) internal view returns (uint256 feeEstimate) {
        // In this case we have to invert the fee calculation
        // We provide a conservative estimate by assuming there is a referrer and rounding up
        (uint48 fee, uint48 referrerFee,) = FeeManager(auctionHouse).fees(auctionType_);
        if (hasReferrer_) fee += referrerFee;

        uint256 numer = price_ * _FEE_DECIMALS;
        uint256 denom = _FEE_DECIMALS - fee;

        return (numer / denom) + ((numer % denom == 0) ? 0 : 1); // round up if necessary
    }
}
