// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IBatchAuction} from "src/interfaces/modules/IBatchAuction.sol";

import {BatchAuctionHouseTest} from "test/BatchAuctionHouse/AuctionHouseTest.sol";

contract BatchAbortTest is BatchAuctionHouseTest {
    // abort
    // [X] when the lot id is not valid
    //    [X] it reverts
    // [X] when the lot hasn't started
    //    [X] it reverts
    // [X] when the lot is active
    //    [X] it reverts
    // [X] when the lot is in the dedicated settle period
    //    [X] it reverts
    // [X] when the lot is cancelled
    //    [X] when before the lot start
    //        [X] it reverts
    //    [X] when in the lot's active period
    //        [X] it reverts
    //    [X] when after the lot's active period
    //        [X] it reverts
    // [X] when the lot is settled
    //    [X] it reverts
    // [X] when the lot is past the dedicated settle period
    //   [X] when a callback is configured
    //    [X] when the callback sends base tokens
    //       [X] it sends the refund to the callback, and calls the cancel() callback
    //    [X] when the callback doesn't send base tokens
    //       [X] it sends the refund to the seller, and calls the cancel() callback
    //    [X] when the callback reverts
    //       [X] it does not revert
    //   [X] when a callback is not configured
    //      [X] it sends the refund to the seller

    modifier givenLotSettlementFinished() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            _scaleQuoteTokenAmount(_LOT_CAPACITY),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            true // marks as finished
        );

        _auctionHouse.settle(_lotId, 100_000, "");
        _;
    }

    function test_abort_whenLotIdIsNotValid_reverts() public {
        // No lots are created

        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, 0);
        vm.expectRevert(err);
        _auctionHouse.abort(0);

        // try a non-zero value too
        err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, 1);
        vm.expectRevert(err);
        _auctionHouse.abort(1);
    }

    function test_abort_whenLotHasNotStarted_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotConcluded.selector, _lotId);
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);
    }

    function test_abort_whenLotActive_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotConcluded.selector, _lotId);
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);
    }

    function test_abort_whenLotInDedicatedSettlePeriod_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotIsConcluded
    {
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId);
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);
    }

    function test_abort_whenLotIsCancelled_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotIsCancelled
    {
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId); // technically in the settle period because the lot is cancelled which updates the conclusion
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);

        // Move timestamp forward to after the lot's dedicated settle period
        vm.warp(block.timestamp + _settlePeriod + 1);

        err = abi.encodeWithSelector(BatchAuctionHouse.InsufficientFunding.selector);
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);
    }

    function test_abort_whenLotIsSettled_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_LOT_CAPACITY)
        givenUserHasQuoteTokenAllowance(_LOT_CAPACITY)
        givenBidCreated(_bidder, _LOT_CAPACITY, "")
        givenLotIsConcluded
        givenLotSettlementFinished
    {
        bytes memory err =
            abi.encodeWithSelector(IBatchAuction.Auction_DedicatedSettlePeriod.selector, _lotId);
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);
    }

    function test_abort_whenLotIsSettled_whenSettlePeriodHasPassed_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_LOT_CAPACITY)
        givenUserHasQuoteTokenAllowance(_LOT_CAPACITY)
        givenBidCreated(_bidder, _LOT_CAPACITY, "")
        givenLotIsConcluded
        givenLotIsPastSettlePeriod
        givenLotSettlementFinished
    {
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);
    }

    function test_abort_whenCallbackSendsBaseTokens()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsConcluded
        givenLotIsPastSettlePeriod
    {
        uint256 startSellerBalance = _baseToken.balanceOf(_SELLER);
        uint256 startCallbackBalance = _baseToken.balanceOf(address(_callback));

        // Abort the lot
        _auctionHouse.abort(_lotId);

        // Check the balances of the seller and the callback
        assertEq(_baseToken.balanceOf(_SELLER), startSellerBalance);
        assertEq(_baseToken.balanceOf(address(_callback)), startCallbackBalance + _LOT_CAPACITY);

        // Check that the callback was called
        assertEq(_callback.lotCancelled(_lotId), true, "onCancel");
    }

    function test_abort_whenCallbackDoesntSendBaseTokens()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsConcluded
        givenLotIsPastSettlePeriod
    {
        uint256 startSellerBalance = _baseToken.balanceOf(_SELLER);
        uint256 startCallbackBalance = _baseToken.balanceOf(address(_callback));

        // Abort the lot
        _auctionHouse.abort(_lotId);

        // Check the balances of the seller and the callback
        assertEq(_baseToken.balanceOf(_SELLER), startSellerBalance + _LOT_CAPACITY);
        assertEq(_baseToken.balanceOf(address(_callback)), startCallbackBalance);

        // Check that the callback was called
        assertEq(_callback.lotCancelled(_lotId), true, "onCancel");
    }

    function test_abort_whenCallbackReverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsConcluded
        givenLotIsPastSettlePeriod
    {
        uint256 startSellerBalance = _baseToken.balanceOf(_SELLER);
        uint256 startCallbackBalance = _baseToken.balanceOf(address(_callback));

        // Set the callback to revert
        _callback.setOnCancelReverts(true);

        // Abort the lot
        _auctionHouse.abort(_lotId);

        // Check the balances of the seller and the callback
        assertEq(_baseToken.balanceOf(_SELLER), startSellerBalance + _LOT_CAPACITY);
        assertEq(_baseToken.balanceOf(address(_callback)), startCallbackBalance);
    }

    function test_abort_whenCallbackNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsConcluded
        givenLotIsPastSettlePeriod
    {
        uint256 startSellerBalance = _baseToken.balanceOf(_SELLER);

        // Abort the lot
        _auctionHouse.abort(_lotId);

        // Check the balance of the seller
        assertEq(_baseToken.balanceOf(_SELLER), startSellerBalance + _LOT_CAPACITY);
    }

    function test_attemptOnCancel_notContract()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsConcluded
        givenLotIsPastSettlePeriod
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IAuctionHouse.NotPermitted.selector, address(this));
        vm.expectRevert(err);

        // Call function
        _auctionHouse.attemptOnCancel(_lotId, _LOT_CAPACITY, abi.encode(""));
    }

    function test_attemptOnCancel()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsConcluded
        givenLotIsPastSettlePeriod
    {
        // Call function
        vm.prank(address(_auctionHouse));
        _auctionHouse.attemptOnCancel(_lotId, _LOT_CAPACITY, abi.encode(""));

        // Check that the callback was called
        assertEq(_callback.lotCancelled(_lotId), true, "onCancel");
    }
}
