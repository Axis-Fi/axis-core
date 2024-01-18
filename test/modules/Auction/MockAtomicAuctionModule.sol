// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {AuctionModule} from "src/modules/Auction.sol";

contract MockAtomicAuctionModule is AuctionModule {
    mapping(uint256 => uint256) public payoutData;
    bool public purchaseReverts;

    struct Output {
        uint256 multiplier;
    }

    mapping(uint256 lotId => bool isCancelled) public cancelled;

    constructor(address _owner) AuctionModule(_owner) {
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("ATOM"), 1);
    }

    function TYPE() public pure virtual override returns (Type) {
        return Type.Auction;
    }

    function _auction(
        uint256,
        Lot memory,
        bytes memory
    ) internal virtual override returns (uint256) {
        return 0;
    }

    function _cancel(uint256 id_) internal override {
        cancelled[id_] = true;
    }

    function purchase(
        uint256 id_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external virtual override returns (uint256 payout, bytes memory auctionOutput) {
        if (purchaseReverts) revert("error");

        if (cancelled[id_]) revert Auction_MarketNotActive(id_);

        if (payoutData[id_] == 0) {
            payout = amount_;
        } else {
            payout = payoutData[id_] * amount_ / 1e5;
        }

        Output memory output = Output({multiplier: 1});

        auctionOutput = abi.encode(output);
    }

    function setPayoutMultiplier(uint256 id_, uint256 multiplier_) external virtual {
        payoutData[id_] = multiplier_;
    }

    function setPurchaseReverts(bool reverts_) external virtual {
        purchaseReverts = reverts_;
    }

    function bid(uint256, uint256, uint256, bytes calldata) external virtual override {
        revert Auction_NotImplemented();
    }

    function settle(uint256 id_) external virtual override returns (uint256[] memory amountsOut) {}

    function settle(
        uint256 id_,
        Bid[] memory bids_
    ) external virtual override returns (uint256[] memory amountsOut) {}

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
}
