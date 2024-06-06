// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IBatchAuction} from "src/interfaces/modules/IBatchAuction.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/batch/EMP/EMP.sol";
import {IEncryptedMarginalPrice} from "src/interfaces/modules/auctions/IEncryptedMarginalPrice.sol";

import {EmpTest} from "test/modules/auctions/EMP/EMPTest.sol";

contract EmpAbortTest is EmpTest {
    uint256 internal constant _BID_AMOUNT = 16e18;
    uint256 internal constant _BID_AMOUNT_OUT = 8e18;

    // abort
    // [X] when the lot id is not valid
    //    [X] it reverts
    // [X] when the lot hasn't started
    //    [X] it reverts
    // [X] when the lot is active
    //    [X] it reverts
    // [X] when the lot is cancelled
    //    [X] when before the lot start
    //        [X] it reverts
    //    [X] when between lot start and conclusion
    //        [X] it reverts
    //    [X] when after lot conclusion
    //        [X] it reverts
    // [X] when the lot is in the dedicated settle period
    //  [X] when the lot's private key is submitted
    //   [X] it reverts
    //  [X] when the lot is decrypted
    //   [X] it reverts
    //  [X] when the lot is settled
    //   [X] it reverts
    //  [X] it reverts
    // [X] when the lot is past the dedicated settle period
    //  [X] when the lot's private key is submitted
    //   [X] it sets the lot status to settled and marginal price to max value
    //  [X] when the lot is decrypted
    //   [X] it sets the lot status to settled and marginal price to max value
    //  [X] when the lot is settled
    //   [X] it reverts
    //  [X] it sets the lot status to settled and marginal price to max value
    // [X] when the lot is aborted
    //  [X] it reverts

    function test_abort_whenLotIdIsNotValid_reverts() public {
        // No lots are created

        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, 0);
        vm.expectRevert(err);
        vm.prank(address(_auctionHouse));
        _module.abort(0);

        // try a non-zero value too
        err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, 1);
        vm.expectRevert(err);
        vm.prank(address(_auctionHouse));
        _module.abort(1);
    }

    function test_abort_whenLotHasNotStarted_reverts() public givenLotIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotConcluded.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenLotActive_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotConcluded.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenLotIsCancelled_beforeStart_reverts()
        public
        givenLotIsCreated
        givenLotIsCancelled
    {
        // Initially after cancelling the auction is in the dedicated settle period because the conclusion timestamp is updated to the current time
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);

        // Warp past the dedicated settle period
        vm.warp(block.timestamp + _settlePeriod + 1);

        // Expect revert
        err = abi.encodeWithSelector(IEncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenLotIsCancelled_afterStartBeforeConclusion_reverts()
        public
        givenLotIsCreated
        givenLotIsCancelled
        givenLotHasStarted
    {
        // Initially after cancelling the auction is in the dedicated settle period because the conclusion timestamp is updated to the current time
        // The start time isn't more than the settle period past the cancellation, so it still reverts with the dedicated settle period error
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);

        // Warp past the dedicated settle period
        vm.warp(block.timestamp + _settlePeriod + 1);

        // Expect revert
        err = abi.encodeWithSelector(IEncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenLotIsCancelled_afterConclusion_reverts()
        public
        givenLotIsCreated
        givenLotIsCancelled
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IEncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenInDedicatedSettlePeriod_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenInDedicatedSettlePeriod_privateKeySubmitted_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenInDedicatedSettlePeriod_decrypted_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenInDedicatedSettlePeriod_settled_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenAfterDedicatedSettlePeriod()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);

        // Check the lot status
        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);

        assertEq(uint8(auctionData.status), uint8(IEncryptedMarginalPrice.LotStatus.Settled));
        assertEq(auctionData.marginalPrice, type(uint256).max);
    }

    function test_abort_whenAfterDedicatedSettlePeriod_privateKeySubmitted()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);

        // Check the lot status
        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);

        assertEq(uint8(auctionData.status), uint8(IEncryptedMarginalPrice.LotStatus.Settled));
        assertEq(auctionData.marginalPrice, type(uint256).max);
    }

    function test_abort_whenAfterDedicatedSettlePeriod_decrypted()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);

        // Check the lot status
        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);

        assertEq(uint8(auctionData.status), uint8(IEncryptedMarginalPrice.LotStatus.Settled));
        assertEq(auctionData.marginalPrice, type(uint256).max);
    }

    function test_abort_whenAfterDedicatedSettlePeriod_settled_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IEncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }

    function test_abort_whenAborted_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT))
        givenLotHasConcluded
        givenLotSettlePeriodHasPassed
        givenLotIsAborted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IEncryptedMarginalPrice.Auction_WrongState.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.abort(_lotId);
    }
}
