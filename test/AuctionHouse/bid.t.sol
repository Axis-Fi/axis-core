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

contract BidTest is Test, Permit2User {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockBatchAuctionModule internal mockAuctionModule;

    AuctionHouse internal auctionHouse;

    uint96 internal lotId;
    uint48 internal auctionDuration = 1 days;

    address internal immutable protocol = address(0x2);
    address internal immutable referrer = address(0x4);
    address internal immutable auctionOwner = address(0x5);
    address internal immutable recipient = address(0x6);

    uint256 internal aliceKey;
    address internal alice;

    uint256 internal constant BID_AMOUNT = 1e18;

    // Function parameters (can be modified)
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;
    Router.BidParams internal bidParams;

    bytes internal auctionData;
    bytes internal allowlistProof;
    bytes internal permit2Data;

    function setUp() external {
        // Set block timestamp
        vm.warp(1_000_000);

        aliceKey = _getRandomUint256();
        alice = vm.addr(aliceKey);

        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(auctionOwner, _PERMIT2_ADDRESS);
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
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            payoutData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode("")
        });

        bidParams = Router.BidParams({
            lotId: lotId,
            recipient: recipient,
            referrer: referrer,
            amount: BID_AMOUNT,
            auctionData: auctionData,
            allowlistProof: allowlistProof,
            permit2Data: permit2Data
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

        // Update bid parameters
        bidParams.lotId = lotId;
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

        // Update bid parameters
        bidParams.lotId = lotId;
        _;
    }

    modifier givenLotHasAllowlist() {
        MockAllowlist allowlist = new MockAllowlist();
        routingParams.allowlist = allowlist;

        // Register a new auction with an allowlist
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);

        // Add the sender to the allowlist
        allowlist.setAllowedWithProof(alice, allowlistProof, true);

        // Update bid parameters
        bidParams.lotId = lotId;
        _;
    }

    modifier withIncorrectAllowlistProof() {
        allowlistProof = abi.encode("incorrect proof");

        // Update bid parameters
        bidParams.allowlistProof = allowlistProof;
        _;
    }

    modifier givenUserHasQuoteTokenBalance(uint256 amount_) {
        quoteToken.mint(alice, amount_);
        _;
    }

    modifier givenUserHasApprovedQuoteToken(uint256 amount_) {
        vm.prank(alice);
        quoteToken.approve(address(auctionHouse), amount_);
        _;
    }

    modifier whenPermit2ApprovalIsProvided() {
        // Approve the Permit2 contract to spend the quote token
        vm.prank(alice);
        quoteToken.approve(_PERMIT2_ADDRESS, type(uint256).max);

        // Set up the Permit2 approval
        uint48 deadline = uint48(block.timestamp);
        uint256 nonce = _getRandomUint256();
        bytes memory signature = _signPermit(
            address(quoteToken), BID_AMOUNT, nonce, deadline, address(auctionHouse), aliceKey
        );

        permit2Data = abi.encode(
            Router.Permit2Approval({deadline: deadline, nonce: nonce, signature: signature})
        );

        // Update bid parameters
        bidParams.permit2Data = permit2Data;
        _;
    }

    // bid
    // [X] given the auction is atomic
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the auction is cancelled
    //  [X] it reverts
    // [X] given the auction is concluded
    //  [X] it reverts
    // [X] given the auction has an allowlist
    //  [X] reverts if the sender is not on the allowlist
    //  [X] it succeeds
    // [X] given the user does not have sufficient balance of the quote token
    //  [X] it reverts
    // [X] when Permit2 approval is provided
    //  [X] it transfers the tokens from the sender using Permit2
    // [X] when Permit2 approval is not provided
    //  [X] it transfers the tokens from the sender
    // [X] it records the bid

    function test_givenAtomicAuction_reverts() external givenLotIsAtomicAuction {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.bid(bidParams);
    }

    function test_whenLotIdIsInvalid_reverts() external givenLotIsCreated whenLotIdIsInvalid {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.bid(bidParams);
    }

    function test_givenLotIsCancelled_reverts() external givenLotIsCreated givenLotIsCancelled {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.bid(bidParams);
    }

    function test_givenLotIsConcluded_reverts() external givenLotIsCreated givenLotIsConcluded {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.bid(bidParams);
    }

    function test_incorrectAllowlistProof_reverts()
        external
        givenLotIsCreated
        givenLotHasAllowlist
        withIncorrectAllowlistProof
    {
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidBidder.selector, alice);
        vm.expectRevert(err);

        // Call the function
        vm.prank(alice);
        auctionHouse.bid(bidParams);
    }

    function test_givenLotHasAllowlist()
        external
        givenLotIsCreated
        givenLotHasAllowlist
        givenUserHasQuoteTokenBalance(BID_AMOUNT)
        givenUserHasApprovedQuoteToken(BID_AMOUNT)
    {
        // Call the function
        vm.prank(alice);
        auctionHouse.bid(bidParams);
    }

    function test_givenUserHasInsufficientBalance_reverts()
        public
        givenLotIsCreated
        givenUserHasApprovedQuoteToken(BID_AMOUNT)
    {
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call the function
        vm.prank(alice);
        auctionHouse.bid(bidParams);
    }

    function test_whenPermit2ApprovalIsProvided()
        external
        givenLotIsCreated
        givenUserHasQuoteTokenBalance(BID_AMOUNT)
        whenPermit2ApprovalIsProvided
    {
        // Call the function
        vm.prank(alice);
        uint256 bidId = auctionHouse.bid(bidParams);

        // Check the balances
        assertEq(quoteToken.balanceOf(alice), 0, "alice: quote token balance mismatch");
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)),
            BID_AMOUNT,
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        Auction.Bid memory bid = mockAuctionModule.getBid(lotId, bidId);
        assertEq(bid.bidder, alice, "bidder mismatch");
        assertEq(bid.recipient, recipient, "recipient mismatch");
        assertEq(bid.referrer, referrer, "referrer mismatch");
        assertEq(bid.amount, BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
        assertEq(bid.auctionParam, auctionData, "auctionParam mismatch");
    }

    function test_whenPermit2ApprovalIsNotProvided()
        external
        givenLotIsCreated
        givenUserHasQuoteTokenBalance(BID_AMOUNT)
        givenUserHasApprovedQuoteToken(BID_AMOUNT)
    {
        // Call the function
        vm.prank(alice);
        uint256 bidId = auctionHouse.bid(bidParams);

        // Check the balances
        assertEq(quoteToken.balanceOf(alice), 0, "alice: quote token balance mismatch");
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)),
            BID_AMOUNT,
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        Auction.Bid memory bid = mockAuctionModule.getBid(lotId, bidId);
        assertEq(bid.bidder, alice, "bidder mismatch");
        assertEq(bid.recipient, recipient, "recipient mismatch");
        assertEq(bid.referrer, referrer, "referrer mismatch");
        assertEq(bid.amount, BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
        assertEq(bid.auctionParam, auctionData, "auctionParam mismatch");
    }

    function test_whenAuctionParamIsProvided()
        external
        givenLotIsCreated
        givenUserHasQuoteTokenBalance(BID_AMOUNT)
        givenUserHasApprovedQuoteToken(BID_AMOUNT)
    {
        auctionData = abi.encode("auction data");

        // Update bid parameters
        bidParams.auctionData = auctionData;

        // Call the function
        vm.prank(alice);
        uint256 bidId = auctionHouse.bid(bidParams);

        // Check the bid
        Auction.Bid memory bid = mockAuctionModule.getBid(lotId, bidId);
        assertEq(bid.auctionParam, auctionData, "auctionParam mismatch");
    }
}
