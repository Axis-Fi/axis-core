// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Veecode, toKeycode, wrapVeecode} from "../../../src/modules/Modules.sol";

// Auctions
import {AuctionModule} from "../../../src/modules/Auction.sol";
import {AtomicAuctionModule} from "../../../src/modules/auctions/AtomicAuctionModule.sol";

contract MockAtomicAuctionModule is AtomicAuctionModule {
    mapping(uint256 => uint256) public payoutData;
    bool public purchaseReverts;

    struct Output {
        uint256 multiplier;
    }

    mapping(uint96 lotId => bool isCancelled) public cancelled;

    constructor(
        address _owner
    ) AuctionModule(_owner) {
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("ATOM"), 1);
    }

    function _auction(uint96, Lot memory, bytes memory) internal virtual override {}

    function _cancelAuction(
        uint96 id_
    ) internal override {
        cancelled[id_] = true;
    }

    function _purchase(
        uint96 lotId_,
        uint256 amount_,
        bytes calldata
    ) internal override returns (uint256 payout, bytes memory auctionOutput) {
        if (purchaseReverts) revert("error");

        if (cancelled[lotId_]) revert Auction_LotNotActive(lotId_);

        // Handle decimals
        uint256 quoteTokenScale = 10 ** lotData[lotId_].quoteTokenDecimals;
        uint256 baseTokenScale = 10 ** lotData[lotId_].baseTokenDecimals;
        uint256 adjustedAmount = (amount_ * baseTokenScale) / quoteTokenScale;

        if (payoutData[lotId_] == 0) {
            payout = uint96(adjustedAmount);
        } else {
            payout = uint96((payoutData[lotId_] * adjustedAmount) / 100e2);
        }

        // Reduce capacity
        lotData[lotId_].capacity -= payout;

        Output memory output = Output({multiplier: 1});

        auctionOutput = abi.encode(output);
    }

    function setPayoutMultiplier(uint96 lotId_, uint256 multiplier_) external virtual {
        payoutData[lotId_] = multiplier_;
    }

    function setPurchaseReverts(
        bool reverts_
    ) external virtual {
        purchaseReverts = reverts_;
    }

    function payoutFor(uint96 lotId_, uint256 amount_) external view override returns (uint256) {}

    function priceFor(uint96 lotId_, uint256 payout_) external view override returns (uint256) {}

    function maxPayout(
        uint96 lotId_
    ) external view override returns (uint256) {}

    function maxAmountAccepted(
        uint96 lotId_
    ) external view override returns (uint256) {}
}
