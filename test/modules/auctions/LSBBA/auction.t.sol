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

contract LSBBACreateAuctionTest is Test, Permit2User {
    address internal constant _PROTOCOL = address(0x1);

    AuctionHouse internal auctionHouse;
    LocalSealedBidBatchAuction internal auctionModule;

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
        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: 10e18,
            implParams: abi.encode(auctionDataParams)
        });
    }

    // ===== Modifiers ===== //

    modifier whenStartTimeIsInPast() {
        auctionParams.start = uint48(block.timestamp - 1);
        _;
    }

    modifier whenStartTimeIsZero() {
        auctionParams.start = 0;
        _;
    }

    modifier whenDurationIsLessThanMinimum() {
        auctionParams.duration = 1;
        _;
    }

    modifier whenAuctionDataParamsAreInvalid() {
        auctionParams.implParams = abi.encode("invalid");
        _;
    }

    modifier whenCapacityInQuoteIsEnabled() {
        auctionParams.capacityInQuote = true;
        _;
    }

    modifier whenMinimumFillPercentageIsMoreThanMax() {
        auctionDataParams.minFillPercent = 100_001;

        auctionParams.implParams = abi.encode(auctionDataParams);
        _;
    }

    modifier whenMinimumBidPercentageIsLessThanMin() {
        auctionDataParams.minBidPercent = 999;

        auctionParams.implParams = abi.encode(auctionDataParams);
        _;
    }

    modifier whenMinimumBidPercentageIsMoreThanMax() {
        auctionDataParams.minBidPercent = 100_001;

        auctionParams.implParams = abi.encode(auctionDataParams);
        _;
    }

    modifier whenPublicKeyModulusIsOfIncorrectLength() {
        auctionDataParams.publicKeyModulus = new bytes(127);

        auctionParams.implParams = abi.encode(auctionDataParams);
        _;
    }

    // ===== Tests ===== //

    // [X] when called by a non-parent
    //  [X] it reverts
    // [X] when start time is in the past
    //  [X] it reverts
    // [X] when start time is zero
    //  [X] it sets the start time to the current block timestamp
    // [X] when the duration is less than the minimum
    //  [X] it reverts
    // [X] when the auction parameters are invalid
    //  [X] it reverts
    // [X] when capacity in quote is enabled
    //  [X] it reverts
    // [X] when minimum fill percentage is more than 100%
    //  [X] it reverts
    // [X] when minimum bid percentage is less than the minimum
    //  [X] it reverts
    // [X] when minimum bid percentage is more than 100%
    //  [X] it reverts
    // [X] when publicKeyModulus is of incorrect length
    //  [X] it reverts
    // [X] when called via execOnModule
    //  [X] it reverts
    // [X] it sets the auction parameters

    function test_notParent_reverts() external {
        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call
        auctionModule.auction(lotId, auctionParams);
    }

    function test_startsInPast_reverts() external whenStartTimeIsInPast {
        // Expected error
        bytes memory err = abi.encodeWithSelector(
            Auction.Auction_InvalidStart.selector, auctionParams.start, uint48(block.timestamp)
        );
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
    }

    function test_noStartTime() external whenStartTimeIsZero {
        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);

        // Check values
        assertEq(auctionModule.getLot(lotId).start, uint48(block.timestamp));
    }

    function test_durationLessThanMinimum_reverts() external whenDurationIsLessThanMinimum {
        // Expected error
        bytes memory err = abi.encodeWithSelector(
            Auction.Auction_InvalidDuration.selector,
            auctionParams.duration,
            auctionModule.minAuctionDuration()
        );
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
    }

    function test_auctionDataParamsAreInvalid_reverts() external whenAuctionDataParamsAreInvalid {
        // Expected error
        vm.expectRevert();

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
    }

    function test_capacityInQuoteIsEnabled_reverts() external whenCapacityInQuoteIsEnabled {
        // Expected error
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
    }

    function test_minimumFillPercentageIsMoreThanMax_reverts()
        external
        whenMinimumFillPercentageIsMoreThanMax
    {
        // Expected error
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
    }

    function test_minimumBidPercentageIsLessThanMin_reverts()
        external
        whenMinimumBidPercentageIsLessThanMin
    {
        // Expected error
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
    }

    function test_minimumBidPercentageIsMoreThanMax_reverts()
        external
        whenMinimumBidPercentageIsMoreThanMax
    {
        // Expected error
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
    }

    function test_publicKeyModulusIsOfIncorrectLength_reverts()
        external
        whenPublicKeyModulusIsOfIncorrectLength
    {
        // Expected error
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams);
    }

    function test_execOnModule() external {
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
            abi.encodeWithSelector(Auction.auction.selector, lotId, auctionParams)
        );
    }

    function test_success() external {
        // Call
        vm.prank(address(auctionHouse));
        (bool prefundingRequired_, uint256 capacity_) = auctionModule.auction(lotId, auctionParams);

        // Check return values
        assertEq(prefundingRequired_, true); // Always true for LSBBA
        assertEq(capacity_, auctionParams.capacity);

        // Check lot data
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.start, auctionParams.start);
        assertEq(lot.conclusion, auctionParams.start + auctionParams.duration);
        assertEq(lot.capacityInQuote, auctionParams.capacityInQuote);
        assertEq(lot.capacity, auctionParams.capacity);

        // Check auction-specific data
        LocalSealedBidBatchAuction.AuctionData memory lotData = auctionModule.getLotData(lotId);
        assertEq(lotData.minimumPrice, auctionDataParams.minimumPrice);
        assertEq(
            lotData.minFilled, (auctionParams.capacity * auctionDataParams.minFillPercent) / 100_000
        );
        assertEq(
            lotData.minBidSize, (auctionParams.capacity * auctionDataParams.minBidPercent) / 100_000
        );
        assertEq(lotData.publicKeyModulus, auctionDataParams.publicKeyModulus);
        assertEq(uint8(lotData.status), uint8(LocalSealedBidBatchAuction.AuctionStatus.Created));

        // Check that the sorted bid queue is initialised
        (uint96 nextBidId_,) = auctionModule.lotSortedBids(lotId);
        assertEq(nextBidId_, 1);
    }
}
