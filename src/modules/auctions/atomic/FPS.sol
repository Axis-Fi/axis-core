// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IAtomicAuction} from "src/interfaces/modules/IAtomicAuction.sol";
import {IFixedPriceSale} from "src/interfaces/modules/auctions/IFixedPriceSale.sol";

// Protocol dependencies
import {Module} from "src/modules/Modules.sol";
import {AuctionModule} from "src/modules/Auction.sol";
import {Veecode, toVeecode} from "src/modules/Modules.sol";
import {AtomicAuctionModule} from "src/modules/auctions/AtomicAuctionModule.sol";

// External libraries
import {FixedPointMathLib as Math} from "lib/solmate/src/utils/FixedPointMathLib.sol";

/// @title  FixedPriceSale
/// @notice A module for creating fixed price sale (atomic) auctions
contract FixedPriceSale is AtomicAuctionModule, IFixedPriceSale {
    // ========== STATE VARIABLES ========== //

    /// @inheritdoc IFixedPriceSale
    mapping(uint96 lotId => AuctionData) public auctionData;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day initially
        minAuctionDuration = 1 days;
    }

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01FPSA");
    }

    // ========== AUCTION ========== //

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes:
    ///             - The lot ID has been validated
    ///             - The start and duration of the lot have been validated
    ///
    ///             This function reverts if:
    ///             - The parameters cannot be decoded into the correct format
    ///             - The price is zero
    ///             - The max payout percent is greater than 100% or less than 1%
    ///
    /// @param      params_    ABI-encoded data of type `IFixedPriceSale.AuctionDataParams`
    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override {
        // Decode the auction params
        AuctionDataParams memory auctionParams = abi.decode(params_, (AuctionDataParams));

        // Validate the price is not zero
        if (auctionParams.price == 0) revert Auction_InvalidParams();

        // Validate the max payout percent is between 1% and 100%
        if (
            auctionParams.maxPayoutPercent < 1e2
                || auctionParams.maxPayoutPercent > _ONE_HUNDRED_PERCENT
        ) revert Auction_InvalidParams();

        // Calculate the max payout
        uint256 maxPayout_ =
            Math.mulDivDown(lot_.capacity, auctionParams.maxPayoutPercent, _ONE_HUNDRED_PERCENT);
        // If capacity in quote, convert max payout to base token using the provided price
        if (lot_.capacityInQuote) {
            maxPayout_ =
                Math.mulDivDown(maxPayout_, 10 ** lot_.baseTokenDecimals, auctionParams.price);
        }

        // Store the auction data
        AuctionData storage data = auctionData[lotId_];
        data.price = auctionParams.price;
        data.maxPayout = maxPayout_;
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes the following:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction has not concluded
    function _cancelAuction(uint96 lotId_) internal pure override {}

    // ========== PURCHASE ========== //

    /// @inheritdoc AtomicAuctionModule
    /// @dev        This function assumes the following:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is active
    ///
    ///             This function reverts if:
    ///             - The payout is less than the minAmountOut specified by the purchaser
    ///             - The payout is greater than the max payout
    ///
    /// @param      auctionData_    ABI-encoded data of type `IFixedPriceSale.PurchaseParams`
    function _purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal view override returns (uint256 payout, bytes memory) {
        // Decode the auction data into the min amount out
        uint256 minAmountOut = abi.decode(auctionData_, (uint256));

        // Calculate the amount of the base token to purchase
        payout = Math.mulDivDown(
            amount_, 10 ** lotData[lotId_].baseTokenDecimals, auctionData[lotId_].price
        );

        // Validate the payout is greater than or equal to the minimum amount out
        if (payout < minAmountOut) revert Auction_InsufficientPayout();

        // Validate the payout is less than the max payout
        if (payout > auctionData[lotId_].maxPayout) revert Auction_PayoutGreaterThanMax();

        return (payout, bytes(""));
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IAtomicAuction
    function payoutFor(uint96 lotId_, uint256 amount_) public view override returns (uint256) {
        return Math.mulDivDown(
            amount_, 10 ** lotData[lotId_].baseTokenDecimals, auctionData[lotId_].price
        );
    }

    /// @inheritdoc IAtomicAuction
    function priceFor(uint96 lotId_, uint256 payout_) public view override returns (uint256) {
        return Math.mulDivUp(
            payout_, auctionData[lotId_].price, 10 ** lotData[lotId_].baseTokenDecimals
        );
    }

    /// @inheritdoc IAtomicAuction
    function maxPayout(uint96 lotId_) public view override returns (uint256) {
        return auctionData[lotId_].maxPayout;
    }

    /// @inheritdoc IAtomicAuction
    function maxAmountAccepted(uint96 lotId_) public view override returns (uint256) {
        return Math.mulDivUp(
            auctionData[lotId_].maxPayout,
            auctionData[lotId_].price,
            10 ** lotData[lotId_].baseTokenDecimals
        );
    }
}
