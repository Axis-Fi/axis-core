// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// Protocol dependencies
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

    struct AuctionData {
        uint96 price;
        uint96 maxPayout;
    }

    struct FixedPriceParams {
        uint96 price;
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

    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01FPAM");
    }

    function TYPE() public pure override returns (Type) {
        return Type.Auction;
    }

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
        if (auctionParams.maxPayoutPercent < 1e3 || auctionParams.maxPayoutPercent > _ONE_HUNDRED_PERCENT) revert Auction_InvalidParams();

        // Calculate the max payout
        uint96 maxPayout = uint96(Math.mulDivDown(lot_.capacity, auctionParams.maxPayoutPercent, _ONE_HUNDRED_PERCENT));
        // If capacity in quote, convert max payout to base token using the provided price
        if (lot_.capacityInQuote) maxPayout = uint96(Math.mulDivDown(maxPayout, 10**lot_.baseTokenDecimals, auctionParams.price));

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
    function _purchase(uint96 lotId_, uint96 amount_, bytes calldata auctionData_) internal view override returns (uint96 payout, bytes memory) {
        // Decode the auction data into the min amount out
        uint96 minAmountOut = abi.decode(auctionData_, (uint96));

        // Calculate the amount of the base token to purchase
        payout = uint96(Math.mulDivDown(amount_, 10 ** lotData[lotId_].baseTokenDecimals, auctionData[lotId_].price));

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
        uint96,
        bytes calldata
    ) internal pure override returns (uint64) {
        revert Auction_NotImplemented();
    }

    function _refundBid(
        uint96,
        uint64,
        address
    ) internal pure override returns (uint96) {
        revert Auction_NotImplemented();
    }

    function _claimBids(
        uint96,
        uint64[] calldata
    ) internal pure override returns (BidClaim[] memory, bytes memory) {
        revert Auction_NotImplemented();
    }

    function _settle(uint96)
        internal
        pure
        override
        returns (Settlement memory, bytes memory) {
            revert Auction_NotImplemented();
        }

    function _claimProceeds(uint96)
        internal
        pure
        override
        returns (uint96, uint96, uint96) {
            revert Auction_NotImplemented();
        }

    function _revertIfLotSettled(uint96) internal view override {}

    function _revertIfLotNotSettled(uint96) internal view override {}

    function _revertIfLotProceedsClaimed(uint96) internal view override {}

    function _revertIfBidInvalid(uint96, uint64) internal view override {}

    function _revertIfNotBidOwner(
        uint96,
        uint64,
        address
    ) internal view override {}

    function _revertIfBidClaimed(uint96, uint64) internal view override {}
}