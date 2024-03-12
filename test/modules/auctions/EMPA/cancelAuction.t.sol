// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleCancelAuctionTest is EmpaModuleTest {
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction has concluded
    //  [X] it reverts
    // [X] when the auction has been cancelled
    //  [X] it reverts
    // [X] when the auction has started
    //  [X] it reverts
    // [X] it updates the conclusion, capacity and status

    function test_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.cancelAuction(_lotId);
    }

    function test_invalidLotId_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_auctionConcluded_reverts() public givenLotIsCreated givenLotHasConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_auctionCancelled_reverts() public givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_auctionStarted_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_success() public givenLotIsCreated {
        // Call the function
        _cancelAuctionLot();

        // Check the state
        Auction.Lot memory lotData = _getAuctionLot(_lotId);
        assertEq(lotData.conclusion, uint48(block.timestamp));
        assertEq(lotData.capacity, 0);

        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Claimed));
    }
}
