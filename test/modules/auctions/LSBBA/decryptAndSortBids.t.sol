// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Tests
import {Test} from "forge-std/Test.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {Module, Veecode, WithModules} from "src/modules/Modules.sol";

// Auctions
import {LocalSealedBidBatchAuction} from "src/modules/auctions/LSBBA/LSBBA.sol";
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {RSAOAEP} from "src/lib/RSA.sol";
import {Bid as QueueBid} from "src/modules/auctions/LSBBA/MinPriorityQueue.sol";

contract LSBBADecryptAndSortBidsTest is Test, Permit2User {
    address internal constant _PROTOCOL = address(0x1);
    address internal alice = address(0x2);
    address internal constant recipient = address(0x3);
    address internal constant referrer = address(0x4);

    AuctionHouse internal auctionHouse;
    LocalSealedBidBatchAuction internal auctionModule;

    uint256 internal constant LOT_CAPACITY = 10e18;

    uint48 internal lotStart;
    uint48 internal lotDuration;
    uint48 internal lotConclusion;

    uint96 internal lotId = 1;
    bytes internal auctionData;
    bytes internal constant PUBLIC_KEY_MODULUS = abi.encodePacked(
        bytes32(0xB925394F570C7C765F121826DFC8A1661921923B33408EFF62DCAC0D263952FE),
        bytes32(0x158C12B2B35525F7568CB8DC7731FBC3739F22D94CB80C5622E788DB4532BD8C),
        bytes32(0x8643680DA8C00A5E7C967D9D087AA1380AE9A031AC292C971EC75F9BD3296AE1),
        bytes32(0x1AFCC05BD15602738CBE9BD75B76403AB2C9409F2CC0C189B4551DEE8B576AD3)
    );

    uint256 internal bidSeed = 1e9;
    uint96 internal bidOne;
    uint256 internal bidOneAmount = 1e18;
    uint256 internal bidOneAmountOut = 3e18;
    LocalSealedBidBatchAuction.Decrypt internal decryptedBidOne;
    uint96 internal bidTwo;
    uint256 internal bidTwoAmount = 1e18;
    uint256 internal bidTwoAmountOut = 2e18;
    LocalSealedBidBatchAuction.Decrypt internal decryptedBidTwo;
    uint96 internal bidThree;
    uint256 internal bidThreeAmount = 1e18;
    uint256 internal bidThreeAmountOut = 7e18;
    LocalSealedBidBatchAuction.Decrypt internal decryptedBidThree;
    LocalSealedBidBatchAuction.Decrypt[] internal decrypts;

    function setUp() public {
        // Ensure the block timestamp is a sane value
        vm.warp(1_000_000);

        // Set up and install the auction module
        auctionHouse = new AuctionHouse(_PROTOCOL, _PERMIT2_ADDRESS);
        auctionModule = new LocalSealedBidBatchAuction(address(auctionHouse));
        auctionHouse.installModule(auctionModule);

        // Set auction data parameters
        LocalSealedBidBatchAuction.AuctionDataParams memory auctionDataParams =
        LocalSealedBidBatchAuction.AuctionDataParams({
            minFillPercent: 1000,
            minBidPercent: 1000,
            minimumPrice: 1e18,
            publicKeyModulus: PUBLIC_KEY_MODULUS
        });

        // Set auction parameters
        lotStart = uint48(block.timestamp) + 1;
        lotDuration = uint48(1 days);
        lotConclusion = lotStart + lotDuration;

        Auction.AuctionParams memory auctionParams = Auction.AuctionParams({
            start: lotStart,
            duration: lotDuration,
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode(auctionDataParams)
        });

        // Create the auction
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);

        // Warp to the start of the auction
        vm.warp(lotStart);

        // Create three bids
        (bidOne, decryptedBidOne) = _createBid(bidOneAmount, bidOneAmountOut);
        (bidTwo, decryptedBidTwo) = _createBid(bidTwoAmount, bidTwoAmountOut);
        (bidThree, decryptedBidThree) = _createBid(bidThreeAmount, bidThreeAmountOut);

        // Set up the decrypts array
        decrypts.push(decryptedBidOne);
        decrypts.push(decryptedBidTwo);
        decrypts.push(decryptedBidThree);
    }

    function _createBid(
        uint256 bidAmount_,
        uint256 bidAmountOut_
    ) internal returns (uint96 bidId_, LocalSealedBidBatchAuction.Decrypt memory decryptedBid_) {
        // Encrypt the bid amount
        LocalSealedBidBatchAuction.Decrypt memory decryptedBid =
            LocalSealedBidBatchAuction.Decrypt({amountOut: bidAmountOut_, seed: bidSeed});
        bytes memory auctionData_ = _encrypt(decryptedBid);

        // Create a bid
        vm.prank(address(auctionHouse));
        bidId_ = auctionModule.bid(lotId, alice, recipient, referrer, bidAmount_, auctionData_);

        return (bidId_, decryptedBid);
    }

    function _encrypt(LocalSealedBidBatchAuction.Decrypt memory decrypt_)
        internal
        view
        returns (bytes memory)
    {
        return RSAOAEP.encrypt(
            abi.encodePacked(decrypt_.amountOut),
            abi.encodePacked(lotId),
            abi.encodePacked(uint24(65_537)),
            PUBLIC_KEY_MODULUS,
            decrypt_.seed
        );
    }

    function _clearDecrypts() internal {
        uint256 len = decrypts.length;
        // Remove all elements
        for (uint256 i = 0; i < len; i++) {
            decrypts.pop();
        }
    }

    // ===== Modifiers ===== //

    modifier whenLotIdIsInvalid() {
        lotId = 2;
        _;
    }

    modifier whenLotHasNotConcluded() {
        vm.warp(lotConclusion - 1);
        _;
    }

    modifier whenLotHasConcluded() {
        vm.warp(lotConclusion + 1);
        _;
    }

    modifier whenLotDecryptionIsComplete() {
        // Decrypt the bids
        auctionModule.decryptAndSortBids(lotId, decrypts);
        _;
    }

    modifier whenDecryptedBidLengthIsGreater() {
        // Decrypt 1 bid
        _clearDecrypts();
        decrypts.push(decryptedBidOne);
        auctionModule.decryptAndSortBids(lotId, decrypts);

        // Prepare to decrypt 3 bids
        _clearDecrypts();
        decrypts.push(decryptedBidTwo);
        decrypts.push(decryptedBidThree);
        decrypts.push(decryptedBidOne);
        _;
    }

    modifier whenDecryptedBidLengthIsZero() {
        // Empty array
        _clearDecrypts();
        _;
    }

    modifier whenBidsAreOutOfOrder() {
        // Re-arrange the bids
        _clearDecrypts();
        decrypts.push(decryptedBidTwo);
        decrypts.push(decryptedBidOne);
        decrypts.push(decryptedBidThree);
        _;
    }

    modifier whenLotHasSettled() {
        // Call for settlement
        vm.prank(address(auctionHouse));
        auctionModule.settle(lotId);
        _;
    }

    modifier whenBidHasBeenCancelled(uint96 bidId_) {
        vm.prank(address(auctionHouse));
        auctionModule.cancelBid(lotId, bidId_, alice);
        _;
    }

    modifier whenDecryptedBidDoesNotMatch() {
        // Change a decrypted bid
        decryptedBidOne.amountOut = decryptedBidOne.amountOut + 1;
        _;
    }

    // ===== Tests ===== //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the caller is the auction house
    //  [X] it succeeds
    // [X] given the lot has not concluded
    //  [X] it reverts
    // [X] given the lot has been fully decrypted
    //  [X] it reverts
    // [X] given the lot has been settled
    //  [X] it reverts
    // [X] when the number of decrypted bids is more than the remaining encrypted bids
    //  [X] it reverts
    // [X] when the decrypted bids array is empty
    //  [X] it does nothing
    // [X] when a decrypted bid does not match the encrypted bid
    //  [X] it reverts
    // [X] when the decrypted bids are out of order
    //  [X] it reverts
    // [X] when a cancelled bid is passed in
    //  [X] it reverts
    // [X] given an encrypted bid has been cancelled
    //  [X] it does not consider the cancelled bid
    // [X] when encrypted bids remain after decryption
    //  [X] it updates the nextDecryptIndex
    // [X] it updates the lot status to decrypted

    function test_whenLotIdIsInvalid_reverts() public whenLotIdIsInvalid {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);
    }

    function test_whenCallerIsAuctionHouse() public whenLotHasConcluded {
        // Call
        vm.prank(address(auctionHouse));
        auctionModule.decryptAndSortBids(lotId, decrypts);
    }

    function test_givenLotHasNotConcluded_reverts() public whenLotHasNotConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);
    }

    function test_givenLotDecryptionIsComplete_reverts()
        public
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);
    }

    function test_givenLotHasSettled_reverts()
        public
        whenLotHasConcluded
        whenLotDecryptionIsComplete
        whenLotHasSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);
    }

    function test_whenDecryptedBidLengthIsGreater_reverts()
        public
        whenLotHasConcluded
        whenDecryptedBidLengthIsGreater
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_InvalidDecrypt.selector);
        vm.expectRevert(err);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);
    }

    function test_whenDecryptedBidsLengthIsZero()
        public
        whenLotHasConcluded
        whenDecryptedBidLengthIsZero
    {
        // Get the index beforehand
        LocalSealedBidBatchAuction.AuctionData memory lotData = auctionModule.getLotData(lotId);
        uint96 nextDecryptIndexBefore = lotData.nextDecryptIndex;

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);

        // Check the index
        lotData = auctionModule.getLotData(lotId);
        assertEq(lotData.nextDecryptIndex, nextDecryptIndexBefore);
    }

    function test_bidsOutOfOrder_reverts() public whenLotHasConcluded whenBidsAreOutOfOrder {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_InvalidDecrypt.selector);
        vm.expectRevert(err);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);
    }

    function test_givenBidHasBeenCancelled_reverts()
        public
        whenBidHasBeenCancelled(bidOne)
        whenLotHasConcluded
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_InvalidDecrypt.selector);
        vm.expectRevert(err);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);
    }

    function test_givenBidHasBeenCancelled()
        public
        whenBidHasBeenCancelled(bidOne)
        whenLotHasConcluded
    {
        // Amend the decrypts array
        _clearDecrypts();
        decrypts.push(decryptedBidThree); // push this first since it swapped with the cancelled one
        decrypts.push(decryptedBidTwo);
        

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);

        // Check values on auction data
        LocalSealedBidBatchAuction.AuctionData memory lotData = auctionModule.getLotData(lotId);
        assertEq(lotData.nextDecryptIndex, 2);
        assertEq(uint8(lotData.status), uint8(LocalSealedBidBatchAuction.AuctionStatus.Decrypted));

        // Check encrypted bids
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBid =
            auctionModule.getBidData(lotId, bidOne);
        assertEq(uint8(encryptedBid.status), uint8(LocalSealedBidBatchAuction.BidStatus.Cancelled));
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBidTwo =
            auctionModule.getBidData(lotId, bidTwo);
        assertEq(
            uint8(encryptedBidTwo.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted)
        );
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBidThree =
            auctionModule.getBidData(lotId, bidThree);
        assertEq(
            uint8(encryptedBidThree.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted)
        );

        // Check sorted bids
        QueueBid memory sortedBidOne = auctionModule.getSortedBidData(lotId, 0);
        assertEq(sortedBidOne.queueId, 0);
        assertEq(sortedBidOne.bidId, bidThree);
        assertEq(sortedBidOne.amountIn, bidThreeAmount);
        assertEq(sortedBidOne.minAmountOut, bidThreeAmountOut);

        QueueBid memory sortedBidTwo = auctionModule.getSortedBidData(lotId, 1);
        assertEq(sortedBidTwo.queueId, 1);
        assertEq(sortedBidTwo.bidId, bidTwo);
        assertEq(sortedBidTwo.amountIn, bidTwoAmount);
        assertEq(sortedBidTwo.minAmountOut, bidTwoAmountOut);

        assertEq(auctionModule.getSortedBidCount(lotId), 2);
    }

    function test_partialDecryption() public whenLotHasConcluded {
        // Amend the decrypts array
        _clearDecrypts();
        decrypts.push(decryptedBidOne);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);

        // Check values on auction data
        LocalSealedBidBatchAuction.AuctionData memory lotData = auctionModule.getLotData(lotId);
        assertEq(lotData.nextDecryptIndex, 1);
        assertEq(uint8(lotData.status), uint8(LocalSealedBidBatchAuction.AuctionStatus.Created));

        // Check encrypted bids
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBid =
            auctionModule.getBidData(lotId, bidOne);
        assertEq(uint8(encryptedBid.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted));
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBidTwo =
            auctionModule.getBidData(lotId, bidTwo);
        assertEq(
            uint8(encryptedBidTwo.status), uint8(LocalSealedBidBatchAuction.BidStatus.Submitted)
        );
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBidThree =
            auctionModule.getBidData(lotId, bidThree);
        assertEq(
            uint8(encryptedBidThree.status), uint8(LocalSealedBidBatchAuction.BidStatus.Submitted)
        );

        // Check sorted bids
        QueueBid memory sortedBidOne = auctionModule.getSortedBidData(lotId, 1);
        assertEq(sortedBidOne.queueId, 1);
        assertEq(sortedBidOne.bidId, bidOne);
        assertEq(sortedBidOne.amountIn, bidOneAmount);
        assertEq(sortedBidOne.minAmountOut, bidOneAmountOut);

        assertEq(auctionModule.getSortedBidCount(lotId), 1);
    }

    function test_partialDecryptionThenFull() public whenLotHasConcluded {
        // Amend the decrypts array
        _clearDecrypts();
        decrypts.push(decryptedBidOne);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);

        // Decrypt the rest
        _clearDecrypts();
        decrypts.push(decryptedBidTwo);
        decrypts.push(decryptedBidThree);

        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);

        // Check values on auction data
        LocalSealedBidBatchAuction.AuctionData memory lotData = auctionModule.getLotData(lotId);
        assertEq(lotData.nextDecryptIndex, 3);
        assertEq(uint8(lotData.status), uint8(LocalSealedBidBatchAuction.AuctionStatus.Decrypted));

        // Check encrypted bids
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBid =
            auctionModule.getBidData(lotId, bidOne);
        assertEq(uint8(encryptedBid.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted));
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBidTwo =
            auctionModule.getBidData(lotId, bidTwo);
        assertEq(
            uint8(encryptedBidTwo.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted)
        );
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBidThree =
            auctionModule.getBidData(lotId, bidThree);
        assertEq(
            uint8(encryptedBidThree.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted)
        );

        // Check sorted bids
        QueueBid memory sortedBidOne = auctionModule.getSortedBidData(lotId, 1);
        assertEq(sortedBidOne.queueId, 2);
        assertEq(sortedBidOne.bidId, bidTwo);
        assertEq(sortedBidOne.amountIn, bidTwoAmount);
        assertEq(sortedBidOne.minAmountOut, bidTwoAmountOut);

        QueueBid memory sortedBidTwo = auctionModule.getSortedBidData(lotId, 2);
        assertEq(sortedBidTwo.queueId, 1);
        assertEq(sortedBidTwo.bidId, bidOne);
        assertEq(sortedBidTwo.amountIn, bidOneAmount);
        assertEq(sortedBidTwo.minAmountOut, bidOneAmountOut);

        QueueBid memory sortedBidThree = auctionModule.getSortedBidData(lotId, 3);
        assertEq(sortedBidThree.queueId, 3);
        assertEq(sortedBidThree.bidId, bidThree);
        assertEq(sortedBidThree.amountIn, bidThreeAmount);
        assertEq(sortedBidThree.minAmountOut, bidThreeAmountOut);

        assertEq(auctionModule.getSortedBidCount(lotId), 3);
    }

    function test_fullDecryption() public whenLotHasConcluded {
        // Call
        auctionModule.decryptAndSortBids(lotId, decrypts);

        // Check values on auction data
        LocalSealedBidBatchAuction.AuctionData memory lotData = auctionModule.getLotData(lotId);
        assertEq(lotData.nextDecryptIndex, 3);
        assertEq(uint8(lotData.status), uint8(LocalSealedBidBatchAuction.AuctionStatus.Decrypted));

        // Check encrypted bids
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBid =
            auctionModule.getBidData(lotId, bidOne);
        assertEq(uint8(encryptedBid.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted));
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBidTwo =
            auctionModule.getBidData(lotId, bidTwo);
        assertEq(
            uint8(encryptedBidTwo.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted)
        );
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBidThree =
            auctionModule.getBidData(lotId, bidThree);
        assertEq(
            uint8(encryptedBidThree.status), uint8(LocalSealedBidBatchAuction.BidStatus.Decrypted)
        );

        // Check sorted bids
        QueueBid memory sortedBidOne = auctionModule.getSortedBidData(lotId, 1);
        assertEq(sortedBidOne.queueId, 2);
        assertEq(sortedBidOne.bidId, bidTwo);
        assertEq(sortedBidOne.amountIn, bidTwoAmount);
        assertEq(sortedBidOne.minAmountOut, bidTwoAmountOut);

        QueueBid memory sortedBidTwo = auctionModule.getSortedBidData(lotId, 2);
        assertEq(sortedBidTwo.queueId, 1);
        assertEq(sortedBidTwo.bidId, bidOne);
        assertEq(sortedBidTwo.amountIn, bidOneAmount);
        assertEq(sortedBidTwo.minAmountOut, bidOneAmountOut);

        QueueBid memory sortedBidThree = auctionModule.getSortedBidData(lotId, 3);
        assertEq(sortedBidThree.queueId, 3);
        assertEq(sortedBidThree.bidId, bidThree);
        assertEq(sortedBidThree.amountIn, bidThreeAmount);
        assertEq(sortedBidThree.minAmountOut, bidThreeAmountOut);

        assertEq(auctionModule.getSortedBidCount(lotId), 3);
    }
}
