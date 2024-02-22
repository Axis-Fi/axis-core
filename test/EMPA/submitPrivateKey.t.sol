// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaSubmitPrivateKeyTest is EmpaTest {
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the lot has not started
    //  [X] it reverts
    // [X] given the lot has started
    //  [X] it reverts
    // [X] given a private key has already been submitted
    //  [X] it reverts
    // [X] when the private key does not match the public key
    //  [X] it reverts
    // [X] it stores the private key
    // [X] add test cases for num of decrypts > 0

    function test_invalidLotId_reverts() external {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.submitPrivateKey(_lotId, _auctionPrivateKey, 0);
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
        _auctionHouse.submitPrivateKey(_lotId, _auctionPrivateKey, 0);
    }

    function test_lotStarted_reverts()
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
        _auctionHouse.submitPrivateKey(_lotId, _auctionPrivateKey, 0);
    }

    function test_privateKeyAlreadySubmitted_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
    {
        // Submit the private key
        _auctionHouse.submitPrivateKey(_lotId, _auctionPrivateKey, 0);

        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call the function
        _auctionHouse.submitPrivateKey(_lotId, _auctionPrivateKey, 0);
    }

    function test_privateKeyDoesNotMatchPublicKey_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Bid_InvalidPrivateKey.selector);
        vm.expectRevert(err);

        // Call the function
        _auctionHouse.submitPrivateKey(_lotId, uint256(1), 0);
    }

    function test_storesPrivateKey()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
    {
        // Call the function
        _auctionHouse.submitPrivateKey(_lotId, _auctionPrivateKey, 0);

        // Assert the state
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.privateKey, _auctionPrivateKey);
    }

    function test_decryptsBids()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(1e18, 2e18)
        givenLotHasConcluded
    {
        // Call the function
        _auctionHouse.submitPrivateKey(_lotId, _auctionPrivateKey, 1);

        // Check the next decrypt index has been updated
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.nextDecryptIndex, 1);

        // Check the lot record
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Decrypted));
    }
}
