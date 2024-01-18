// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {AuctionModule} from "src/modules/Auction.sol";

contract MockBatchAuctionModule is AuctionModule {
    constructor(address _owner) AuctionModule(_owner) {
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("BATCH"), 1);
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
        uint256,
        uint256,
        bytes calldata
    ) external virtual override returns (uint256, bytes memory) {
        revert Auction_NotImplemented();
    }

    function bid(uint256, uint256, uint256, bytes calldata) external virtual override {}

    function settle(uint256 id_) external virtual override returns (uint256[] memory amountsOut) {}

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

    function settle(
        uint256 id_,
        Bid[] calldata winningBids_,
        bytes[] calldata bidSignatures_,
        uint256[] memory amountsIn_,
        uint256[] calldata amountsOut_,
        bytes calldata validityProof_
    ) external virtual override returns (bytes memory) {}
}