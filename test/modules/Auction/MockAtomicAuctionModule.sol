// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {AuctionModule} from "src/modules/Auction.sol";

contract MockAtomicAuctionModule is AuctionModule {
    mapping(uint256 => uint256) public payoutData;
    bool public purchaseReverts;
    bool public requiresPrefunding;

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

    function setRequiredPrefunding(bool prefunding_) external virtual {
        requiresPrefunding = prefunding_;
    }

    function _auction(uint96, Lot memory, bytes memory) internal virtual override returns (bool) {
        return requiresPrefunding;
    }

    function _cancelAuction(uint96 id_) internal override {
        cancelled[id_] = true;
    }

    function _purchase(
        uint96 id_,
        uint256 amount_,
        bytes calldata
    ) internal override returns (uint256 payout, bytes memory auctionOutput) {
        if (purchaseReverts) revert("error");

        if (cancelled[id_]) revert Auction_MarketNotActive(id_);

        if (payoutData[id_] == 0) {
            payout = amount_;
        } else {
            payout = (payoutData[id_] * amount_) / 1e5;
        }

        // Reduce capacity
        lotData[id_].capacity -= payout;

        Output memory output = Output({multiplier: 1});

        auctionOutput = abi.encode(output);
    }

    function setPayoutMultiplier(uint256 id_, uint256 multiplier_) external virtual {
        payoutData[id_] = multiplier_;
    }

    function setPurchaseReverts(bool reverts_) external virtual {
        purchaseReverts = reverts_;
    }

    function _bid(
        uint96,
        address,
        address,
        address,
        uint256,
        bytes calldata
    ) internal pure override returns (uint96) {
        revert Auction_NotImplemented();
    }

    function _cancelBid(uint96, uint96, address) internal virtual override returns (uint256) {
        revert Auction_NotImplemented();
    }

    function settle(
        uint256 id_,
        Bid[] memory bids_
    ) external virtual returns (uint256[] memory amountsOut) {}

    function payoutFor(
        uint256 id_,
        uint256 amount_
    ) public view virtual override returns (uint256) {}

    function priceFor(
        uint256 id_,
        uint256 payout_
    ) public view virtual override returns (uint256) {}

    function maxPayout(uint256 id_) public view virtual override returns (uint256) {}

    function maxAmountAccepted(uint256 id_) public view virtual override returns (uint256) {}

    function _settle(uint96) internal pure override returns (Bid[] memory, bytes memory) {
        revert Auction_NotImplemented();
    }

    function _revertIfBidInvalid(uint96 lotId_, uint96 bidId_) internal view virtual override {}

    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint96 bidId_,
        address caller_
    ) internal view virtual override {}

    function _revertIfBidCancelled(uint96 lotId_, uint96 bidId_) internal view virtual override {}

    function _revertIfLotSettled(uint96 lotId_) internal view virtual override {}
}
