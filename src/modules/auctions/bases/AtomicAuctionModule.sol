// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// Protocol dependencies
import {Module} from "src/modules/Modules.sol";
import {AuctionModule, Auction} from "src/modules/Auction.sol";

abstract contract AtomicAuctionModule is AuctionModule {
    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {}

    /// @inheritdoc Module
    function TYPE() public pure override returns (Type) {
        return Type.Auction;
    }

    /// @inheritdoc Auction
    function auctionType() external pure override returns (AuctionType) {
        return AuctionType.Atomic;
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

    function _refundBid(uint96, uint64, address) internal pure override returns (uint96) {
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

    function _claimProceeds(uint96) internal pure override returns (uint96, uint96, uint96) {
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
