// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auctioneer} from "src/bases/Auctioneer.sol";
import {Auction} from "src/modules/Auction.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract RefundBidTest is AuctionHouseTest {
    uint96 internal constant _BID_AMOUNT = 1e18;
    bytes internal _auctionDataParams = abi.encode("");

    modifier givenBidIsRefunded() {
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
        _;
    }

    // refundBid
    // [X] given the auction lot does not exist
    //  [X] it reverts
    // [X] given the auction lot is an atomic auction
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
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_invalidAuctionType_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_lotConcluded_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, _auctionDataParams)
        givenLotIsConcluded
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_givenBidDoesNotExist_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        bytes memory err =
            abi.encodeWithSelector(Auction.Auction_InvalidBidId.selector, _lotId, _bidId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_givenBidRefunded_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, _auctionDataParams)
        givenBidIsRefunded
    {
        bytes memory err =
            abi.encodeWithSelector(Auction.Auction_InvalidBidId.selector, _lotId, _bidId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_givenCallerIsNotBidOwner_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, _auctionDataParams)
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotBidder.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_SELLER);
        _auctionHouse.refundBid(_lotId, _bidId);
    }

    function test_itRefundsTheBid()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, _auctionDataParams)
    {
        // Get _bidder's balance
        uint256 aliceBalance = _quoteToken.balanceOf(_bidder);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, _bidId);

        // Assert the bid is cancelled
        assertTrue(_batchAuctionModule.bidCancelled(_lotId, _bidId));

        // Expect _bidder's balance to increase
        assertEq(_quoteToken.balanceOf(_bidder), aliceBalance + _BID_AMOUNT);
    }
}
