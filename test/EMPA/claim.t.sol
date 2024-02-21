// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaClaimTest is EmpaTest {
    uint96 internal constant _BID_AMOUNT = 1e18;
    uint96 internal constant _BID_AMOUNT_OUT = 2e18;

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the lot is not concluded
    //  [X] it reverts
    // [X] given the lot is not decrypted
    //  [X] it reverts
    // [X] given the lot is not settled
    //  [X] it reverts
    // [X] when the bid id is invalid
    //  [X] it reverts
    // [X] given the bid has been claimed
    //  [X] it reverts
    // [X] given the bid was not successful
    //  [X] given the caller is not the bidder
    //   [X] it refunds the bid amount to the bidder
    //  [X] it refunds the bid amount to the bidder
    // [X] given the caller is not the bidder
    //  [X] it sends the payout to the bidder
    // [X] it sends the payout to the bidder

    function test_invalidLotId_reverts() external {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenLotNotConcluded_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenLotNotDecrypted_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenLotNotSettled_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_invalidBidId_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Bid_InvalidId.selector, _lotId, _bidId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenBidClaimed_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Claim the bid
        _auctionHouse.claim(_lotId, _bidId);

        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Bid_WrongState.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenBidNotSuccessful_givenCallerIsNotBidder()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), _BID_AMOUNT);
        assertEq(_baseToken.balanceOf(_bidder), 0);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));
    }

    function test_givenBidNotSuccessful()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), _BID_AMOUNT);
        assertEq(_baseToken.balanceOf(_bidder), 0);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));
    }

    function test_givenBidSuccessful_givenCallerIsNotBidder()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT_OUT, _BID_AMOUNT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), 0);
        assertEq(_baseToken.balanceOf(_bidder), _BID_AMOUNT_OUT);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));
    }

    function test_givenBidSuccessful()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT_OUT, _BID_AMOUNT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), 0);
        assertEq(_baseToken.balanceOf(_bidder), _BID_AMOUNT_OUT);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));
    }

    // TODO handle decimals
}
