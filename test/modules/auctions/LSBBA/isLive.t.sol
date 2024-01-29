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

contract LSBBAIsLiveTest is Test, Permit2User {
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

    // Function parameters
    uint96 internal lotId = 1;
    Auction.AuctionParams internal auctionParams;
    LocalSealedBidBatchAuction.AuctionDataParams internal auctionDataParams;

    function setUp() public {
        // Ensure the block timestamp is a sane value
        vm.warp(1_000_000);

        // Set up and install the auction module
        auctionHouse = new AuctionHouse(_PROTOCOL, _PERMIT2_ADDRESS);
        auctionModule = new LocalSealedBidBatchAuction(address(auctionHouse));
        auctionHouse.installModule(auctionModule);

        // Set auction data parameters
        auctionDataParams = LocalSealedBidBatchAuction.AuctionDataParams({
            minFillPercent: 1000,
            minBidPercent: 1000,
            minimumPrice: 1e18,
            publicKeyModulus: new bytes(128)
        });

        // Set auction parameters
        lotStart = uint48(block.timestamp) + 1;
        lotDuration = uint48(1 days);
        lotConclusion = lotStart + lotDuration;

        auctionParams = Auction.AuctionParams({
            start: lotStart,
            duration: lotDuration,
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode(auctionDataParams)
        });

        // Create the auction
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
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

    modifier givenLotIsCancelled() {
        vm.prank(address(auctionHouse));
        auctionModule.cancelAuction(lotId);
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

    // ===== Tests ===== //

    // [X] false if lot id is invalid
    // [X] false if lot has not started
    // [X] false if lot has been cancelled
    // [X] false if lot has concluded
    // [X] false if lot has been decrypted
    // [X] false if lot has been settled
    // [X] true if lot is live

    function test_lotIdIsInvalid() public whenLotIdIsInvalid givenLotHasStarted {
        assertEq(auctionModule.isLive(lotId), false);
    }

    function test_lotHasNotStarted() public {
        assertEq(auctionModule.isLive(lotId), false);
    }

    function test_lotIsCancelled() public givenLotIsCancelled {
        assertEq(auctionModule.isLive(lotId), false);
    }

    function test_lotHasConcluded() public givenLotHasConcluded {
        assertEq(auctionModule.isLive(lotId), false);
    }

    function test_lotHasDecrypted() public givenLotHasConcluded givenLotHasDecrypted {
        assertEq(auctionModule.isLive(lotId), false);
    }

    function test_lotHasSettled()
        public
        givenLotHasConcluded
        givenLotHasDecrypted
        givenLotHasSettled
    {
        assertEq(auctionModule.isLive(lotId), false);
    }

    function test_lotIsActive() public givenLotHasStarted {
        assertEq(auctionModule.isLive(lotId), true);
    }
}
