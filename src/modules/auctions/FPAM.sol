// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// Protocol dependencies
import {Module} from "src/modules/Modules.sol";
import {AuctionModule, Auction} from "src/modules/Auction.sol";
import {Veecode, toVeecode} from "src/modules/Modules.sol";

// Libraries
import {FixedPointMathLib as Math} from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract FixedPriceAuctionModule is AuctionModule {
    // ========== ERRORS ========== //

    error Auction_InsufficientPayout();
    error Auction_PayoutGreaterThanMax();

    // ========== EVENTS ========== //

    // ========== DATA STRUCTURES ========== //

    /// @notice             Auction-specific data for a lot
    ///
    /// @param price        The fixed price of the lot
    /// @param maxPayout    The maximum payout per purchase, in terms of the base token
    struct AuctionData {
        uint256 price;
        uint256 maxPayout;
    }

    /// @notice                     Parameters for a fixed price auction
    ///
    /// @param price                The fixed price of the lot
    /// @param maxPayoutPercent     The maximum payout per purchase, as a percentage of the capacity
    struct FixedPriceParams {
        uint256 price;
        uint24 maxPayoutPercent;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     Auction-specific data for a lot
    mapping(uint96 lotId => AuctionData) public auctionData;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day initially
        minAuctionDuration = 1 days;
    }

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01FPAM");
    }

    /// @inheritdoc Module
    function TYPE() public pure override returns (Type) {
        return Type.Auction;
    }

    /// @inheritdoc Auction
    function auctionType() external pure override returns (AuctionType) {
        return AuctionType.Atomic;
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
    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override {
        // Decode the auction params
        FixedPriceParams memory auctionParams = abi.decode(params_, (FixedPriceParams));

        // Validate the price is not zero
        if (auctionParams.price == 0) revert Auction_InvalidParams();

        // Validate the max payout percent is between 1% and 100%
        if (
            auctionParams.maxPayoutPercent < 1e3
                || auctionParams.maxPayoutPercent > _ONE_HUNDRED_PERCENT
        ) revert Auction_InvalidParams();

        // Calculate the max payout
        uint256 maxPayout =
            Math.mulDivDown(lot_.capacity, auctionParams.maxPayoutPercent, _ONE_HUNDRED_PERCENT);
        // If capacity in quote, convert max payout to base token using the provided price
        if (lot_.capacityInQuote) {
            maxPayout =
                Math.mulDivDown(maxPayout, 10 ** lot_.baseTokenDecimals, auctionParams.price);
        }

        // Store the auction data
        AuctionData storage data = auctionData[lotId_];
        data.price = auctionParams.price;
        data.maxPayout = maxPayout;
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes the following:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction has not concluded
    function _cancelAuction(uint96 lotId_) internal pure override {}

    // ========== PURCHASE ========== //

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes the following:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is active
    ///
    ///             This function reverts if:
    ///             - The payout is less than the minAmountOut specified by the purchaser
    ///             - The payout is greater than the max payout
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

    // ========== NOT IMPLEMENTED ========== //

    function _bid(
        uint96,
        address,
        address,
        uint256,
        bytes calldata
    ) internal pure override returns (uint64) {
        revert Auction_NotImplemented();
    }

    function _refundBid(uint96, uint64, address) internal pure override returns (uint256) {
        revert Auction_NotImplemented();
    }

    function _claimBids(
        uint96,
        uint64[] calldata
    ) internal pure override returns (BidClaim[] memory, bytes memory) {
        revert Auction_NotImplemented();
    }

    function _settle(uint96) internal pure override returns (Settlement memory, bytes memory) {
        revert Auction_NotImplemented();
    }

    function _claimProceeds(uint96) internal pure override returns (uint256, uint256, uint256) {
        revert Auction_NotImplemented();
    }

    function _revertIfLotSettled(uint96) internal pure override {
        revert Auction_NotImplemented();
    }

    function _revertIfLotNotSettled(uint96) internal pure override {
        revert Auction_NotImplemented();
    }

    function _revertIfLotProceedsClaimed(uint96) internal pure override {
        revert Auction_NotImplemented();
    }

    function _revertIfBidInvalid(uint96, uint64) internal pure override {
        revert Auction_NotImplemented();
    }

    function _revertIfNotBidOwner(uint96, uint64, address) internal pure override {
        revert Auction_NotImplemented();
    }

    function _revertIfBidClaimed(uint96, uint64) internal pure override {
        revert Auction_NotImplemented();
    }
}
