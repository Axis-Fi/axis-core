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

contract LSBBABidTest is Test, Permit2User {
    address internal constant _PROTOCOL = address(0x1);
    address internal constant alice = address(0x2);
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

    uint256 internal MIN_BID_SIZE;
    uint256 internal bidAmount = 1e18;

    uint8 internal constant _quoteTokenDecimals = 18;
    uint8 internal constant _baseTokenDecimals = 18;

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
            publicKeyModulus: new bytes(128)
        });

        // Set auction parameters
        lotStart = uint48(block.timestamp) + 1;
        lotDuration = uint48(1 days);
        lotConclusion = lotStart + lotDuration;
        MIN_BID_SIZE = 1000 * LOT_CAPACITY / 100_000;

        Auction.AuctionParams memory auctionParams = Auction.AuctionParams({
            start: lotStart,
            duration: lotDuration,
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode(auctionDataParams)
        });

        // Create the auction
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams, _quoteTokenDecimals, _baseTokenDecimals);

        auctionData = abi.encode(1e9); // Encrypted amount out
    }

    // ===== Modifiers ===== //

    modifier whenLotIdIsInvalid() {
        lotId = 2;
        _;
    }

    modifier givenLotHasStarted() {
        vm.warp(lotStart + 1);
        _;
    }

    modifier givenLotHasConcluded() {
        vm.warp(lotConclusion + 1);
        _;
    }

    modifier givenLotHasDecrypted() {
        // Decrypt the bids (none)
        LocalSealedBidBatchAuction.Decrypt[] memory decrypts =
            new LocalSealedBidBatchAuction.Decrypt[](0);
        auctionModule.decryptAndSortBids(lotId, decrypts);
        _;
    }

    modifier givenLotHasSettled() {
        // Call for settlement
        vm.prank(address(auctionHouse));
        auctionModule.settle(lotId);
        _;
    }

    modifier whenAmountIsSmallerThanMinimumBidAmount() {
        bidAmount = MIN_BID_SIZE - 1;
        _;
    }

    modifier whenAmountIsLargerThanCapacity() {
        bidAmount = LOT_CAPACITY + 1;
        _;
    }

    // ===== Tests ===== //

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot has not started
    //  [X] it reverts
    // [X] when the lot has concluded
    //  [X] it reverts
    // [X] when the lot has decrypted
    //  [X] it reverts
    // [X] when the lot has settled
    //  [X] it reverts
    // [X] when the amount is smaller than the minimum bid amount
    //  [X] it reverts
    // [X] when the amount is larger than the capacity
    //  [X] it reverts
    // [X] when the caller is using execOnModule
    //  [X] it reverts
    // [X] it records the encrypted bid

    function test_whenCallerIsNotParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call
        auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);
    }

    function test_whenLotIdIsInvalid_reverts() public whenLotIdIsInvalid givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);
    }

    function test_whenLotHasNotStarted_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);
    }

    function test_whenLotHasConcluded_reverts() public givenLotHasConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);
    }

    function test_whenLotHasDecrypted_reverts() public givenLotHasConcluded givenLotHasDecrypted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);
    }

    function test_whenLotHasSettled_reverts()
        public
        givenLotHasConcluded
        givenLotHasDecrypted
        givenLotHasSettled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);
    }

    function test_whenAmountIsSmallerThanMinimumBidAmount()
        public
        givenLotHasStarted
        whenAmountIsSmallerThanMinimumBidAmount
    {
        // Call
        vm.prank(address(auctionHouse));
        uint96 bidId = auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);

        // Check values
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBid =
            auctionModule.getBidData(lotId, bidId);
        assertEq(encryptedBid.bidder, alice);
        assertEq(encryptedBid.recipient, recipient);
        assertEq(encryptedBid.referrer, referrer);
        assertEq(encryptedBid.amount, bidAmount);
        assertEq(encryptedBid.encryptedAmountOut, auctionData);
        assertEq(uint8(encryptedBid.status), uint8(LocalSealedBidBatchAuction.BidStatus.Submitted));
    }

    function test_whenAmountIsLargerThanCapacity()
        public
        givenLotHasStarted
        whenAmountIsLargerThanCapacity
    {
        // Call
        vm.prank(address(auctionHouse));
        uint96 bidId = auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);

        // Check values
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBid =
            auctionModule.getBidData(lotId, bidId);
        assertEq(encryptedBid.bidder, alice);
        assertEq(encryptedBid.recipient, recipient);
        assertEq(encryptedBid.referrer, referrer);
        assertEq(encryptedBid.amount, bidAmount);
        assertEq(encryptedBid.encryptedAmountOut, auctionData);
        assertEq(uint8(encryptedBid.status), uint8(LocalSealedBidBatchAuction.BidStatus.Submitted));
    }

    function test_execOnModule_reverts() public {
        Veecode moduleVeecode = auctionModule.VEECODE();

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleExecutionReverted.selector,
            abi.encodeWithSelector(Module.Module_OnlyInternal.selector)
        );
        vm.expectRevert(err);

        // Call
        auctionHouse.execOnModule(
            moduleVeecode,
            abi.encodeWithSelector(
                Auction.bid.selector, lotId, alice, recipient, referrer, bidAmount, auctionData
            )
        );
    }

    function test_itRecordsTheEncryptedBid() public givenLotHasStarted {
        // Call
        vm.prank(address(auctionHouse));
        uint96 bidId = auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);

        // Check values
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBid =
            auctionModule.getBidData(lotId, bidId);
        assertEq(encryptedBid.bidder, alice);
        assertEq(encryptedBid.recipient, recipient);
        assertEq(encryptedBid.referrer, referrer);
        assertEq(encryptedBid.amount, bidAmount);
        assertEq(encryptedBid.encryptedAmountOut, auctionData);
        assertEq(uint8(encryptedBid.status), uint8(LocalSealedBidBatchAuction.BidStatus.Submitted));
    }
}
