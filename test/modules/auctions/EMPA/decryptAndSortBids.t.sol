// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleDecryptBidsTest is EmpaModuleTest {
    uint96 internal constant _BID_AMOUNT = 2e18;
    uint96 internal constant _BID_AMOUNT_OUT = 1e18;

    uint96 internal constant _BID_AMOUNT_SMALL = 1e17;
    uint96 internal constant _BID_AMOUNT_OUT_SMALL = 1e16;

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the lot has not started
    //  [X] it reverts
    // [X] given the lot has not concluded
    //  [X] it reverts
    // [X] given the private key has not been submitted
    //  [X] it reverts
    // [X] given the bids are already decrypted
    //  [X] it reverts
    // [X] given the lot has been cancelled
    //  [X] it reverts
    // [X] given the lot has been settled
    //  [X] it reverts
    // [X] given the lot proceeds have been claimed
    //  [X] it reverts
    // [X] when the number of bids to decrypt is larger than the number of bids
    //  [X] it succeeds
    // [X] given a bid cannot be decrypted
    //  [X] the bid is marked as decrypted, with the minAmountOut set to 0
    // [X] given a bid amount out is larger than supported
    //  [X] the bid is marked as decrypted, with the minAmountOut set to 0
    // [X] given the marginal price overflows
    //  [X] the bid is marked as decrypted, with the minAmountOut set to 0
    // [X] when the number of bids to decrypt is larger than the number of bids
    //  [X] it decrypts the bids, updates bid records and updates the lot status
    // [X] given a bid amount out is smaller than the minimum bid size
    //  [X] given quote token decimals are larger
    //   [X] it is handled correctly
    //  [X] given quote token decimals are smaller
    //   [X] it is handled correctly
    //  [X] the bid record is updated, but it is not added to the decrypted bids queue
    // [X] when there are no bids to decrypt
    //  [X] the lot is marked as decrypted
    // [X] when the number of bids to decrypt is smaller than the number of bids
    //  [X] it decrypts the specified number of bids, but does not update the lot status
    // [X] when the bids have been partially decrypted
    //  [X] it decrypts the remaining bids and updates the lot status

    function test_invalidLotId_reverts() external {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _module.decryptAndSortBids(_lotId, 0);
    }

    function test_lotHasNotStarted_reverts() external givenLotIsCreated {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _module.decryptAndSortBids(_lotId, 0);
    }

    function test_lotHasNotConcluded_reverts() external givenLotIsCreated givenLotHasStarted {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        _module.decryptAndSortBids(_lotId, 0);
    }

    function test_privateKeyNotSubmitted_reverts()
        external
        givenLotIsCreated
        givenLotHasConcluded
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        _module.decryptAndSortBids(_lotId, 0);
    }

    function test_alreadyDecrypted_reverts()
        external
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        _module.decryptAndSortBids(_lotId, 0);
    }

    function test_givenLotIsSettled_reverts()
        external
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
    {
        // Call the function
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        _module.decryptAndSortBids(_lotId, 0);
    }

    function test_givenLotProceedsAreClaimed_reverts()
        external
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
        givenLotProceedsAreClaimed
    {
        // Call the function
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        _module.decryptAndSortBids(_lotId, 0);
    }

    function test_givenLotIsCancelled_reverts() external givenLotIsCreated givenLotIsCancelled {
        // Call the function
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _module.decryptAndSortBids(_lotId, 0);
    }

    function test_incorrectBidEncryption() external givenLotIsCreated givenLotHasStarted {
        // Create a bid using a different auction private key
        uint256 auctionPrivateKey = 1;
        uint256 encryptedBidAmountOut =
            _encryptBid(_lotId, _BIDDER, _BID_AMOUNT, _BID_AMOUNT_OUT, auctionPrivateKey);
        bytes memory bidInput = abi.encode(encryptedBidAmountOut, _bidPublicKey);
        vm.prank(address(_auctionHouse));
        _bidId = _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidInput);

        // Conclude the lot
        _concludeLot();
        _submitPrivateKey();

        // Call the function
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(bidData.minAmountOut, 0, "minAmountOut");
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid status"
        );

        // Check the bid queue
        (uint64 numBids) = _module.decryptedBids(_lotId);
        assertEq(numBids, 0, "decryptedBids");

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }

    function test_givenBidAmountOverflows() external givenLotIsCreated givenLotHasStarted {
        // Create a bid with an amount that exceeds uint96
        uint128 bidAmountOut = type(uint128).max - 1;
        uint256 encryptedBidAmountOut = _encryptBid(_lotId, _BIDDER, _BID_AMOUNT, bidAmountOut);
        bytes memory bidInput = abi.encode(encryptedBidAmountOut, _bidPublicKey);
        vm.prank(address(_auctionHouse));
        _bidId = _module.bid(_lotId, _BIDDER, _REFERRER, _BID_AMOUNT, bidInput);

        // Conclude the lot
        _concludeLot();
        _submitPrivateKey();

        // Call the function
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(bidData.minAmountOut, 0, "minAmountOut");
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid status"
        );

        // Check the bid queue
        (uint64 numBids) = _module.decryptedBids(_lotId);
        assertEq(numBids, 0, "decryptedBids");

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }

    function test_givenMarginalPriceOverflows()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(type(uint96).max, 1e17)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(bidData.minAmountOut, 0, "minAmountOut");
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid status"
        );

        // Check the bid queue
        (uint64 numBids) = _module.decryptedBids(_lotId);
        assertEq(numBids, 0, "decryptedBids");

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }

    function test_givenSmallestPossibleMarginalPrice()
        external
        givenMinimumPrice(1)
        givenMinimumBidPercentage(10)
        givenBaseTokenDecimals(6)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1, type(uint96).max)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(bidData.minAmountOut, type(uint96).max, "minAmountOut");
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid status"
        );

        // Check the bid queue
        (uint64 numBids) = _module.decryptedBids(_lotId);
        assertEq(numBids, 1, "decryptedBids");

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }

    function test_numberOfBidsToDecryptIsLargerThanNumberOfBids_succeeds()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _module.decryptAndSortBids(_lotId, 10);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(bidData.minAmountOut, _BID_AMOUNT_OUT);
        assertEq(
            uint8(bidData.status), uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted)
        );

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1);
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted));
    }

    function test_belowMinimumBidSize()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT_SMALL, _BID_AMOUNT_OUT_SMALL)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(bidData.minAmountOut, 0, "minAmountOut");
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid status"
        );

        // Check the bid queue
        (uint64 numBids) = _module.decryptedBids(_lotId);
        assertEq(numBids, 0, "decryptedBids");

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }

    function test_belowMinimumBidSize_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(
            _scaleQuoteTokenAmount(_BID_AMOUNT_SMALL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_SMALL)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(bidData.minAmountOut, 0, "minAmountOut");
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid status"
        );

        // Check the bid queue
        (uint64 numBids) = _module.decryptedBids(_lotId);
        assertEq(numBids, 0, "decryptedBids");

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }

    function test_belowMinimumBidSize_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(
            _scaleQuoteTokenAmount(_BID_AMOUNT_SMALL),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT_SMALL)
        )
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, _bidId);
        assertEq(bidData.minAmountOut, 0, "minAmountOut");
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid status"
        );

        // Check the bid queue
        (uint64 numBids) = _module.decryptedBids(_lotId);
        assertEq(numBids, 0, "decryptedBids");

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }

    function test_noBids()
        external
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // No need to call decrypt, as the lot is already marked as decrypted by submitPrivateKey

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }

    function test_partialDecrypt()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidDataOne = _getBid(_lotId, 1);
        assertEq(bidDataOne.minAmountOut, _BID_AMOUNT_OUT, "bid one: minAmountOut");
        assertEq(
            uint8(bidDataOne.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid one: status"
        );

        EncryptedMarginalPriceAuctionModule.Bid memory bidDataTwo = _getBid(_lotId, 2);
        assertEq(bidDataTwo.minAmountOut, 0, "bid two: minAmountOut");
        assertEq(
            uint8(bidDataTwo.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Submitted),
            "bid two: status"
        );

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 1, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Created), "auction status");
    }

    function test_partialDecrypt_remainingBids()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Call the function to decrypt 1 bid
        _module.decryptAndSortBids(_lotId, 1);

        // Call the function to decrypt the remaining bid
        _module.decryptAndSortBids(_lotId, 1);

        // Check the bid state
        EncryptedMarginalPriceAuctionModule.Bid memory bidDataOne = _getBid(_lotId, 1);
        assertEq(bidDataOne.minAmountOut, _BID_AMOUNT_OUT, "bid one: minAmountOut");
        assertEq(
            uint8(bidDataOne.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid one: status"
        );

        EncryptedMarginalPriceAuctionModule.Bid memory bidDataTwo = _getBid(_lotId, 2);
        assertEq(bidDataTwo.minAmountOut, _BID_AMOUNT_OUT, "bid two: minAmountOut");
        assertEq(
            uint8(bidDataTwo.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid two: status"
        );

        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.nextDecryptIndex, 2, "nextDecryptIndex");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "auction status");
    }
}
