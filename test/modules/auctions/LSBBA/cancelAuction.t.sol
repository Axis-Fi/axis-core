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

contract LSBBACancelAuctionTest is Test, Permit2User {
    address internal constant _PROTOCOL = address(0x1);

    AuctionHouse internal auctionHouse;
    LocalSealedBidBatchAuction internal auctionModule;

    uint48 internal lotStart;
    uint48 internal lotDuration;
    uint48 internal lotConclusion;

    // Function parameters
    uint96 internal lotId = 1;
    Auction.AuctionParams internal auctionParams;
    LocalSealedBidBatchAuction.AuctionDataParams internal auctionDataParams;

    uint8 internal constant _quoteTokenDecimals = 18;
    uint8 internal constant _baseTokenDecimals = 18;

    function setUp() public {
        // Ensure the block timestamp is a sane value
        vm.warp(1_000_000);

        // Set up and install the auction module
        auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _PERMIT2_ADDRESS);
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
            capacity: 10e18,
            implParams: abi.encode(auctionDataParams)
        });

        // Create the auction
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
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

    // ===== Tests ===== //

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the auction has already started
    //  [X] it reverts
    // [X] given the auction decryption has started
    //  [X] it reverts
    // [X] given the auction has concluded
    //  [X] it reverts
    // [X] given the auction has been settled
    //  [X] it reverts
    // [X] when the caller is using execOnModule
    //  [X] it reverts
    // [X] it marks the auction as settled

    function test_whenCallerIsNotParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call
        auctionModule.cancelAuction(lotId);
    }

    function test_whenLotIdIsInvalid_reverts() public whenLotIdIsInvalid {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelAuction(lotId);
    }

    function test_givenLotHasStarted_reverts() public givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelAuction(lotId);
    }

    function test_givenLotHasConcluded_reverts() public givenLotHasConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelAuction(lotId);
    }

    function test_givenLotHasDecrypted_reverts() public givenLotHasConcluded givenLotHasDecrypted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelAuction(lotId);
    }

    function test_givenLotHasSettled_reverts()
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
        auctionModule.cancelAuction(lotId);
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
            moduleVeecode, abi.encodeWithSelector(Auction.cancelAuction.selector, lotId)
        );
    }

    function test_success() public {
        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelAuction(lotId);

        // Assert Lot values
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.conclusion, block.timestamp);
        assertEq(lot.capacity, 0);

        // Assert Auction values
        LocalSealedBidBatchAuction.AuctionData memory auctionData = auctionModule.getLotData(lotId);
        assertEq(uint8(auctionData.status), uint8(LocalSealedBidBatchAuction.AuctionStatus.Settled));
    }
}
