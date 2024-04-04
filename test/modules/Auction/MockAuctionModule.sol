// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {Auction, AuctionModule} from "src/modules/Auction.sol";

contract MockAuctionModule is AuctionModule {
    constructor(address _owner) AuctionModule(_owner) {
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("MOCK"), 1);
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
        //
    }

    function _purchase(
        uint96 id_,
        uint96 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint96 payout, bytes memory auctionOutput) {}

    function _bid(
        uint96 id_,
        address bidder_,
        address referrer_,
        uint96 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint64) {}

    function _settle(uint96 lotId_) internal override returns (Settlement memory, bytes memory) {}

    function _claimProceeds(uint96 lotId_) internal override returns (uint96, uint96, uint96) {}

    function _refundBid(
        uint96 lotId_,
        uint64 bidId_,
        address bidder_
    ) internal virtual override returns (uint96) {}

    function _claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    ) internal virtual override returns (BidClaim[] memory bidClaims, bytes memory auctionOutput) {}

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

contract MockAuctionModuleV2 is MockAuctionModule {
    constructor(address _owner) MockAuctionModule(_owner) {}

    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("MOCK"), 2);
    }
}
