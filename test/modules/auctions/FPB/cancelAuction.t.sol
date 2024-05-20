// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbCancelAuctionTest is FpbTest {
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction has concluded
    //  [X] it reverts
    // [X] when the auction has been cancelled
    //  [X] it reverts
    // [X] when the auction has been aborted
    //  [X] it reverts
    // [X] when the auction has been settled
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_auctionConcluded_reverts(uint48 conclusionElapsed_) public givenLotIsCreated {
        uint48 conclusionElapsed = uint48(bound(conclusionElapsed_, 0, 1 days));

        // Warp to the conclusion
        vm.warp(_start + _DURATION + conclusionElapsed);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_auctionCancelled_reverts() public givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_auctionAborted_reverts()
        public
        givenLotIsCreated
        givenLotSettlePeriodHasPassed
        givenLotIsAborted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_auctionSettled_reverts()
        public
        givenLotIsCreated
        givenLotHasConcluded
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_auctionStarted_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IFixedPriceBatch.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _cancelAuctionLot();
    }

    function test_success() public givenLotIsCreated {
        // Call the function
        _cancelAuctionLot();

        // Assert state
        IAuction.Lot memory lotData = _module.getLot(_lotId);
        assertEq(lotData.conclusion, uint48(block.timestamp), "conclusion");
        assertEq(lotData.capacity, 0, "capacity");

        IFixedPriceBatch.AuctionData memory auctionData = _module.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(IFixedPriceBatch.LotStatus.Settled), "status");
    }
}
