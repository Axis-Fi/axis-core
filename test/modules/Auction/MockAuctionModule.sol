// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {AuctionModule} from "src/modules/Auction.sol";

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

    function _auction(
        uint256,
        Lot memory,
        bytes memory
    ) internal virtual override returns (uint256) {
        return 0;
    }

    function _cancel(uint256 id_) internal override {
        //
    }

    function purchase(
        uint256 id_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external virtual override returns (uint256 payout, bytes memory auctionOutput) {}

    function bid(
        uint96 id_,
        address recipient_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_,
        bytes calldata approval_
    ) external virtual override {}

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

    function settle(
        uint96 lotId_,
        Bid[] calldata winningBids_,
        bytes calldata settlementProof_,
        bytes calldata settlementData_
    ) external virtual override returns (uint256[] memory amountsOut, bytes memory auctionOutput) {}
}

contract MockAuctionModuleV2 is MockAuctionModule {
    constructor(address _owner) MockAuctionModule(_owner) {}

    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("MOCK"), 2);
    }
}
