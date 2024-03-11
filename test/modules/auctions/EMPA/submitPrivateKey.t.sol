// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleSubmitPrivateKeyTest is EmpaModuleTest {
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot is active
    //  [X] it reverts
    // [X] given the lot has been cancelled
    //  [X] it reverts
    // [X] when the lot has not started
    //  [X] it reverts
    // [X] given the private key has already been submitted
    //  [X] it reverts
    // [X] when the public key is not derived from the private key
    //  [X] it reverts
    // [X] when the caller is not the parent
    //  [X] it succeeds
    // [X] when the number of bids to decrypt is specified
    //  [X] it decrypts the bids
    // [X] it sets the private key

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);
    }

    function test_lotIsActive_reverts() external givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);
    }

    function test_lotHasNotStarted_reverts() external givenLotIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);
    }

    function test_lotCancelled_reverts() external givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);
    }

    function test_privateKeyAlreadySubmitted_reverts()
        external
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);
    }

    function test_privateKeyNotDerivedFromPublicKey_reverts()
        external
        givenLotIsCreated
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuctionModule.Auction_InvalidKey.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.submitPrivateKey(_lotId, uint256(1), 0);
    }

    function test_success()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotHasConcluded
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);

        // Assert the private key is set
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.privateKey, _AUCTION_PRIVATE_KEY);

        // Assert that the bids are not decrypted
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, 1);
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Submitted),
            "bid status"
        );
    }

    function test_notParent()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotHasConcluded
    {
        // Call the function
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);

        // Assert the private key is set
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.privateKey, _AUCTION_PRIVATE_KEY);

        // Assert that the bids are not decrypted
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, 1);
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Submitted),
            "bid status"
        );
    }

    function test_decryptBids()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(2e18, 1e18)
        givenLotHasConcluded
    {
        // Call the function
        vm.prank(address(_auctionHouse));
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 1);

        // Assert the private key is set
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.privateKey, _AUCTION_PRIVATE_KEY);

        // Assert that the bids are not decrypted
        EncryptedMarginalPriceAuctionModule.Bid memory bidData = _getBid(_lotId, 1);
        assertEq(
            uint8(bidData.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid status"
        );
    }
}
