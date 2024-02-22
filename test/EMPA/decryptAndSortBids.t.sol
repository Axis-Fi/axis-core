// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaDecryptBidsTest is EmpaTest {
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the lot has not started
    //  [X] it reverts
    // [X] given the lot has not concluded
    //  [X] it reverts
    // [X] given the private key has not been submitted
    //  [X] it reverts
    // [X] when the number of bids to decrypt is larger than the number of bids
    //  [X] it succeeds
    // [X] given a bid cannot be decrypted
    //  [X] it is ignored
    // [X] given a bid amount out is larger than supported
    //  [X] it is ignored
    // [X] when the number of bids to decrypt is smaller than the number of bids
    //  [X] it updates the nextDecryptIndex
    // [X] given a bid amount out is smaller than the minimum bid size
    //  [X] the bid record is updated, but it is not added to the decrypted bids queue
    // [X] given the bids are already decrypted
    //  [X] it reverts
    // [X] when there are no bids to decrypt
    //  [X] the lot is marked as decrypted
    // [X] it decrypts the bids and updates bid records

    function test_invalidLotId_reverts() external {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 0);
    }

    function test_lotNotStarted_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketNotActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 0);
    }

    function test_lotNotConcluded_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 0);
    }

    function test_privateKeyNotSubmitted_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 0);
    }

    function test_alreadyDecrypted_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // No need to call decrypt, as it is called by submitPrivateKey

        // Call the function again
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 0);
    }

    function test_belowMinimumBidSize()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18, _minBidSize - 1)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 1);

        // Check the bid record
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1);
        assertEq(bid.amount, 1e18);
        assertEq(bid.minAmountOut, _minBidSize - 1);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Decrypted));

        // Check the decrypted bids queue
        (uint64 numBids) = _auctionHouse.decryptedBids(_lotId);
        assertEq(numBids, 0);

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Decrypted));
    }

    function test_incorrectBidEncryption(uint128 bidAmount_)
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Create an unencrypted bid
        uint256 unencryptedBidAmount = _formatBid(bidAmount_);
        uint96 amountIn = 1e18;

        // Mint quote tokens to the bidder
        _quoteToken.mint(_bidder, amountIn);

        // Approve spending
        vm.prank(_bidder);
        _quoteToken.approve(address(_auctionHouse), amountIn);

        // Bid
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId, _REFERRER, amountIn, unencryptedBidAmount, _bidPublicKey, bytes(""), bytes("")
        );

        _concludeLot();
        _submitPrivateKey();

        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 1);

        // Check the next decrypt index has been updated
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.nextDecryptIndex, 1);

        // Check the bids
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Submitted));

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Decrypted));
    }

    function test_noBids()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // No need to call decrypt, as it is called by submitPrivateKey

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Decrypted));
    }

    function test_whenNumberOfBidsSmaller()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18, 2e18)
        givenBidIsCreated(1e18, 2e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 1);

        // Check the next decrypt index has been updated
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.nextDecryptIndex, 1);

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Created));
    }

    function test_whenNumberOfBidsSmaller_thenCompleteDecryption()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18, 2e18)
        givenBidIsCreated(1e18, 2e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 1);
        _auctionHouse.decryptAndSortBids(_lotId, 1);

        // Check the next decrypt index has been updated
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.nextDecryptIndex, 2);

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Decrypted));
    }

    function test_whenNumberOfBidsLarger()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 2e18)
        givenBidIsCreated(3e18, 1e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 3);

        // Check the next decrypt index has been updated
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.nextDecryptIndex, 2, "nextDecryptIndex mismatch");

        // Check the bids
        EncryptedMarginalPriceAuction.Bid memory bid1 = _getBid(_lotId, 1);
        assertEq(
            uint8(bid1.status),
            uint8(EncryptedMarginalPriceAuction.BidStatus.Decrypted),
            "bid1 status mismatch"
        );
        assertEq(bid1.minAmountOut, 2e18, "bid1 minAmountOut mismatch");
        EncryptedMarginalPriceAuction.Bid memory bid2 = _getBid(_lotId, 2);
        assertEq(
            uint8(bid2.status),
            uint8(EncryptedMarginalPriceAuction.BidStatus.Decrypted),
            "bid2 status mismatch"
        );
        assertEq(bid2.minAmountOut, 1e18, "bid2 minAmountOut mismatch");

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(
            uint8(lot.status),
            uint8(EncryptedMarginalPriceAuction.AuctionStatus.Decrypted),
            "lot status mismatch"
        );
    }

    function test_whenBidAmountIsOutOfBounds()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLargeBidIsCreated(1e18, type(uint128).max - 1)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 1);

        // Check the next decrypt index has been updated
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.nextDecryptIndex, 1);

        // Check the bids
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Submitted));

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Decrypted));
    }

    function test_whenMarginalPriceOutOfBounds()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(type(uint96).max, 1e17)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _auctionHouse.decryptAndSortBids(_lotId, 1);

        // Check the next decrypt index has been updated
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.nextDecryptIndex, 1);

        // Check the bids
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Submitted));

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Decrypted));
    }

    // TODO handle decimals
}
