// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";

import {BatchAuctionHouseTest} from "test/BatchAuctionHouse/AuctionHouseTest.sol";

contract BatchAbortTest is BatchAuctionHouseTest {
    // abort
    // [X] when the lot id is not valid
    //    [X] it reverts
    // [X] when the lot hasn't started
    //    [X] it reverts
    // [X] when the lot is active
    //    [X] it reverts
    // [X] when the lot is cancelled
    //    [X] it reverts
    // [X] when the lot is settled
    //    [X] it reverts
    // [ ] when a callback is configured that sends base tokens
    //    [ ] it sends the refund to the callback
    // [ ] when a callback is not configured
    //    [ ] it sends the refund to the seller
    // [ ] when a callback is configured that doesn't send base tokens
    //    [ ] it sends the refund to the seller

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

        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidLotId.selector, 0);
        vm.expectRevert(err);
        _auctionHouse.abort(0);

        // try a non-zero value too
        err = abi.encodeWithSelector(AuctionHouse.InvalidLotId.selector, 1);
        vm.expectRevert(err);
        _auctionHouse.abort(1);
    }

    // // TODO is it possible to reach this with funding == 0?
    // function test_abort_whenFundingIsZero_reverts() public
    //     whenAuctionTypeIsBatch
    //     whenBatchAuctionModuleIsInstalled
    //     givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
    //     givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    //     givenLotIsCreated
    //     givenLotIsCancelled
    // {
    //     // We cancel the lot to set the funding to zero

    //     bytes memory err = abi.encodeWithSelector(BatchAuctionHouse.InsufficientFunding.selector, _lotId);
    //     vm.expectRevert(err);
    //     _auctionHouse.abort(_lotId);
    // }

    function test_abort_whenLotHasNotStarted_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketActive.selector, _lotId);
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);

        // Move timestamp forward to during the lot's active period
        vm.warp(_startTime + 1);
        err = abi.encodeWithSelector(BatchAuctionHouse.InsufficientFunding.selector);
        vm.expectRevert(err);
        _auctionHouse.abort(_lotId);

        // Move timestamp forward to after the lot's active period
        vm.warp(_startTime + _duration + 1);
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_MarketNotActive.selector, _lotId);
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
    {
        uint256 startSellerBalance = _baseToken.balanceOf(_SELLER);
        uint256 startCallbackBalance = _baseToken.balanceOf(address(_callback));

        // Abort the lot
        _auctionHouse.abort(_lotId);

        // Check the balances of the seller and the callback
        assertEq(_baseToken.balanceOf(_SELLER), startSellerBalance);
        assertEq(_baseToken.balanceOf(address(_callback)), startCallbackBalance + _LOT_CAPACITY);
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
    {
        uint256 startSellerBalance = _baseToken.balanceOf(_SELLER);
        uint256 startCallbackBalance = _baseToken.balanceOf(address(_callback));

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
    {
        uint256 startSellerBalance = _baseToken.balanceOf(_SELLER);

        // Abort the lot
        _auctionHouse.abort(_lotId);

        // Check the balance of the seller
        assertEq(_baseToken.balanceOf(_SELLER), startSellerBalance + _LOT_CAPACITY);
    }
}
