// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaRefundBidTest is EmpaTest {
    uint96 internal constant _BID_AMOUNT = 1e18;
    uint96 internal constant _BID_AMOUNT_OUT = 2e18;

    // refundBid
    // [X] given the auction lot does not exist
    //  [X] it reverts
    // [X] given the auction lot is concluded
    //  [X] it reverts
    // [X] given the bid does not exist
    //  [X] it reverts
    // [X] given the bid is already cancelled
    //  [X] it reverts
    // [X] given the caller is not the bid owner
    //  [X] it reverts
    // [X] it cancels the bid and transfers the quote tokens back to the bidder

    function test_invalidLotId_reverts() external {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_lotConcluded_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketNotActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_givenBidDoesNotExist_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Bid_InvalidId.selector, _lotId, _bidId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_givenBidRefunded_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenBidIsRefunded(_bidId)
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Bid_WrongState.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_givenCallerIsNotBidOwner_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.NotPermitted.selector, _auctionOwner
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_auctionOwner);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_itRefundsTheBid()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
    {
        // Get _bidder's balance
        uint256 aliceBalance = _quoteToken.balanceOf(_bidder);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);

        // Expect _bidder's balance to increase
        assertEq(_quoteToken.balanceOf(_bidder), aliceBalance + _BID_AMOUNT);

        // Assert the bid is cancelled
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Refunded));
    }

    // TODO handle decimals
}
