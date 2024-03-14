// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {Auction, AuctionModule} from "src/modules/Auction.sol";

contract MockAtomicAuctionModule is AuctionModule {
    mapping(uint256 => uint256) public payoutData;
    bool public purchaseReverts;

    struct Output {
        uint256 multiplier;
    }

    mapping(uint96 lotId => bool isCancelled) public cancelled;

    constructor(address _owner) AuctionModule(_owner) {
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("ATOM"), 1);
    }

    function TYPE() public pure virtual override returns (Type) {
        return Type.Auction;
    }

    /// @inheritdoc Auction
    function auctionType() external pure override returns (AuctionType) {
        return AuctionType.Atomic;
    }

    function _auction(uint96, Lot memory, bytes memory) internal virtual override {}

    function _cancelAuction(uint96 id_) internal override {
        cancelled[id_] = true;
    }

    function _purchase(
        uint96 lotId_,
        uint96 amount_,
        bytes calldata
    ) internal override returns (uint96 payout, bytes memory auctionOutput) {
        if (purchaseReverts) revert("error");

        if (cancelled[lotId_]) revert Auction_MarketNotActive(lotId_);

        // Handle decimals
        uint256 quoteTokenScale = 10 ** lotData[lotId_].quoteTokenDecimals;
        uint256 baseTokenScale = 10 ** lotData[lotId_].baseTokenDecimals;
        uint256 adjustedAmount = amount_ * baseTokenScale / quoteTokenScale;

        if (payoutData[lotId_] == 0) {
            payout = uint96(adjustedAmount);
        } else {
            payout = uint96((payoutData[lotId_] * adjustedAmount) / 1e5);
        }

        // Reduce capacity
        lotData[lotId_].capacity -= uint96(payout);

        Output memory output = Output({multiplier: 1});

        auctionOutput = abi.encode(output);
    }

    function setPayoutMultiplier(uint96 lotId_, uint256 multiplier_) external virtual {
        payoutData[lotId_] = multiplier_;
    }

    function setPurchaseReverts(bool reverts_) external virtual {
        purchaseReverts = reverts_;
    }

    function _bid(
        uint96,
        address,
        address,
        uint96,
        bytes calldata
    ) internal pure override returns (uint64) {
        revert Auction_NotImplemented();
    }

    function _refundBid(uint96, uint64, address) internal virtual override returns (uint96) {
        revert Auction_NotImplemented();
    }

    function _claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    ) internal virtual override returns (BidClaim[] memory bidClaims, bytes memory auctionOutput) {}

    function settle(uint96) external pure override returns (Settlement memory, bytes memory) {
        revert Auction_NotImplemented();
    }

    function _settle(uint96) internal pure override returns (Settlement memory, bytes memory) {
        revert Auction_NotImplemented();
    }

    function claimProceeds(uint96) external pure override returns (uint96, uint96, uint96) {
        revert Auction_NotImplemented();
    }

    function _claimProceeds(uint96) internal pure override returns (uint96, uint96, uint96) {
        revert Auction_NotImplemented();
    }

    function _revertIfBidInvalid(uint96 lotId_, uint64 bidId_) internal view virtual override {}

    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) internal view virtual override {}

    function _revertIfBidClaimed(uint96 lotId_, uint64 bidId_) internal view virtual override {}

    function _revertIfLotSettled(uint96 lotId_) internal view virtual override {}

    function _revertIfLotNotSettled(uint96 lotId_) internal view virtual override {}

    function _revertIfLotProceedsClaimed(uint96 lotId_) internal view virtual override {}
}
