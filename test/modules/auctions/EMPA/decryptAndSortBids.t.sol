// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
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
    // [X] when the number of bids to decrypt is larger than the number of bids
    //  [X] it succeeds
    // [ ] given a bid cannot be decrypted
    //  [ ] it is ignored
    // [ ] given a bid amount out is larger than supported
    //  [ ] it is ignored
    // [ ] when the number of bids to decrypt is smaller than the number of bids
    //  [ ] it updates the nextDecryptIndex
    // [ ] given a bid amount out is smaller than the minimum bid size
    //  [ ] the bid record is updated, but it is not added to the decrypted bids queue
    // [ ] given the bids are already decrypted
    //  [ ] it reverts
    // [ ] when there are no bids to decrypt
    //  [ ] the lot is marked as decrypted
    // [ ] it decrypts the bids and updates bid records

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
}
