// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";

// Auctions
import {AuctionHouse, Router} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {IHooks, IAllowlist, Auctioneer} from "src/bases/Auctioneer.sol";

// Modules
import {
    Keycode,
    toKeycode,
    Veecode,
    wrapVeecode,
    unwrapVeecode,
    fromVeecode,
    WithModules,
    Module
} from "src/modules/Modules.sol";

contract RefundBidTest is Test, Permit2User {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockBatchAuctionModule internal mockAuctionModule;

    AuctionHouse internal auctionHouse;

    uint48 internal auctionDuration = 1 days;

    address internal immutable protocol = address(0x2);
    address internal immutable referrer = address(0x4);
    address internal immutable auctionOwner = address(0x5);
    address internal immutable recipient = address(0x6);
    address internal immutable alice = address(0x7);

    uint256 internal constant BID_AMOUNT = 1e18;

    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    // Function parameters (can be modified)
    uint96 internal lotId;
    uint96 internal bidId;

    function setUp() external {
        // Set block timestamp
        vm.warp(1_000_000);

        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(address(this), auctionOwner, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockBatchAuctionModule(address(auctionHouse));

        auctionHouse.installModule(mockAuctionModule);

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: auctionDuration,
            capacityInQuote: false,
            capacity: 10e18,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("BATCH"),
            baseToken: baseToken,
            quoteToken: quoteToken,
            curator: address(0),
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            infoHash: abi.encode("")
        });
    }

    modifier givenLotIsCreated() {
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    modifier givenLotIsAtomicAuction() {
        // Install the atomic auction module
        MockAtomicAuctionModule mockAtomicAuctionModule =
            new MockAtomicAuctionModule(address(auctionHouse));
        auctionHouse.installModule(mockAtomicAuctionModule);

        // Update routing parameters
        (Keycode moduleKeycode,) = unwrapVeecode(mockAtomicAuctionModule.VEECODE());
        routingParams.auctionType = moduleKeycode;

        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    modifier givenLotIsCancelled() {
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);
        _;
    }

    modifier givenLotIsConcluded() {
        vm.warp(block.timestamp + auctionDuration + 1);
        _;
    }

    modifier whenLotIdIsInvalid() {
        lotId = 255;
        _;
    }

    modifier givenBidIsCreated() {
        // Mint quote tokens to alice
        quoteToken.mint(alice, BID_AMOUNT);

        // Approve spending
        vm.prank(alice);
        quoteToken.approve(address(auctionHouse), BID_AMOUNT);

        // Create the bid
        Router.BidParams memory bidParams = Router.BidParams({
            lotId: lotId,
            recipient: recipient,
            referrer: referrer,
            amount: BID_AMOUNT,
            auctionData: bytes(""),
            allowlistProof: bytes(""),
            permit2Data: bytes("")
        });

        vm.prank(alice);
        auctionHouse.bid(bidParams);
        _;
    }

    modifier givenBidIsRefunded() {
        vm.prank(alice);
        auctionHouse.refundBid(lotId, bidId);
        _;
    }

    // refundBid
    // [X] given the auction lot does not exist
    //  [X] it reverts
    // [X] given the auction lot is an atomic auction
    //  [X] it reverts
    // [X] given the auction lot is concluded
    //  [X] it reverts
    // [X] given the bid does not exist
    //  [X] it reverts
    // [X] given the bid is already cancelled
    //  [X] it reverts
    // [X] given the caller is not the bid owner
    //  [X] it reverts
    // [X] it cancels the bid and transfers the quote tokens back to the bidder

    function test_invalidLotId_reverts() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.refundBid(lotId, bidId);
    }

    function test_invalidAuctionType_reverts() external givenLotIsAtomicAuction {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.refundBid(lotId, bidId);
    }

    function test_lotConcluded_reverts()
        external
        givenLotIsCreated
        givenBidIsCreated
        givenLotIsConcluded
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.refundBid(lotId, bidId);
    }

    function test_givenBidDoesNotExist_reverts() external givenLotIsCreated {
        bytes memory err =
            abi.encodeWithSelector(Auction.Auction_InvalidBidId.selector, lotId, bidId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.refundBid(lotId, bidId);
    }

    function test_givenBidRefunded_reverts()
        external
        givenLotIsCreated
        givenBidIsCreated
        givenBidIsRefunded
    {
        bytes memory err =
            abi.encodeWithSelector(Auction.Auction_InvalidBidId.selector, lotId, bidId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.refundBid(lotId, bidId);
    }

    function test_givenCallerIsNotBidOwner_reverts() external givenLotIsCreated givenBidIsCreated {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotBidder.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(auctionOwner);
        auctionHouse.refundBid(lotId, bidId);
    }

    function test_itRefundsTheBid() external givenLotIsCreated givenBidIsCreated {
        // Get alice's balance
        uint256 aliceBalance = quoteToken.balanceOf(alice);

        // Call the function
        vm.prank(alice);
        auctionHouse.refundBid(lotId, bidId);

        // Assert the bid is cancelled
        assertTrue(mockAuctionModule.bidCancelled(lotId, bidId));

        // Expect alice's balance to increase
        assertEq(quoteToken.balanceOf(alice), aliceBalance + BID_AMOUNT);
    }
}
