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
import {uint2str} from "src/lib/Uint2Str.sol";

contract LSBBACancelBidTest is Test, Permit2User {
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

    uint96 internal bidId;
    uint256 internal bidAmount = 1e18;
    bytes32 internal bidSeed = bytes32(uint256(1e9));
    LocalSealedBidBatchAuction.Decrypt internal decryptedBid;

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
        auctionModule.auction(lotId, auctionParams, _quoteTokenDecimals, _baseTokenDecimals);

        // Warp to the start of the auction
        vm.warp(lotStart);

        // Encrypt the bid amount
        decryptedBid = LocalSealedBidBatchAuction.Decrypt({amountOut: bidAmount, seed: bidSeed});
        auctionData = _encrypt(decryptedBid);

        // Create a bid
        vm.prank(address(auctionHouse));
        bidId = auctionModule.bid(lotId, alice, recipient, referrer, bidAmount, auctionData);
    }

    function _encrypt(LocalSealedBidBatchAuction.Decrypt memory decrypt_)
        internal
        view
        returns (bytes memory)
    {
        return RSAOAEP.encrypt(
            abi.encodePacked(decrypt_.amountOut),
            abi.encodePacked(uint2str(lotId)),
            abi.encodePacked(uint24(65_537)),
            PUBLIC_KEY_MODULUS,
            decrypt_.seed
        );
    }

    // ===== Modifiers ===== //

    modifier whenLotIdIsInvalid() {
        lotId = 2;
        _;
    }

    modifier whenBidIdIsInvalid() {
        bidId = 2;
        _;
    }

    modifier whenCallerIsNotBidder() {
        alice = address(0x10);
        _;
    }

    modifier givenLotHasConcluded() {
        vm.warp(lotConclusion + 1);
        _;
    }

    modifier givenLotHasDecrypted() {
        // Decrypt the bids
        LocalSealedBidBatchAuction.Decrypt[] memory decrypts =
            new LocalSealedBidBatchAuction.Decrypt[](1);
        decrypts[0] = decryptedBid;

        auctionModule.decryptAndSortBids(lotId, decrypts);
        _;
    }

    modifier givenLotHasSettled() {
        // Call for settlement
        vm.prank(address(auctionHouse));
        auctionModule.settle(lotId);
        _;
    }

    modifier givenBidHasBeenCancelled() {
        vm.prank(address(auctionHouse));
        auctionModule.cancelBid(lotId, bidId, alice);
        _;
    }

    // ===== Tests ===== //

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the bid id is invalid
    //  [X] it reverts
    // [X] when the caller is not the bidder
    //  [X] it reverts
    // [X] when the lot has concluded
    //  [X] it reverts
    // [X] when the lot has decrypted
    //  [X] it reverts
    // [X] when the lot has settled
    //  [X] it reverts
    // [X] when the bid has already been cancelled
    //  [X] it reverts
    // [X] when the caller is using execOnModule
    //  [X] it reverts
    // [X] it updates the bid details

    function test_whenCallerIsNotParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call
        auctionModule.cancelBid(lotId, bidId, alice);
    }

    function test_whenLotIdIsInvalid_reverts() public whenLotIdIsInvalid {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelBid(lotId, bidId, alice);
    }

    function test_whenBidIdIsInvalid_reverts() public whenBidIdIsInvalid {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Auction.Auction_InvalidBidId.selector, lotId, bidId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelBid(lotId, bidId, alice);
    }

    function test_whenCallerIsNotBidder_reverts() public whenCallerIsNotBidder {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotBidder.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelBid(lotId, bidId, alice);
    }

    function test_givenLotHasConcluded_reverts() public givenLotHasConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelBid(lotId, bidId, alice);
    }

    function test_givenLotHasDecrypted_reverts() public givenLotHasConcluded givenLotHasDecrypted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelBid(lotId, bidId, alice);
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
        auctionModule.cancelBid(lotId, bidId, alice);
    }

    function test_givenBidHasBeenCancelled_reverts() public givenBidHasBeenCancelled {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_AlreadyCancelled.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        auctionModule.cancelBid(lotId, bidId, alice);
    }

    function test_whenCallerIsUsingExecOnModule_reverts() public {
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
            abi.encodeWithSelector(auctionModule.cancelBid.selector, lotId, bidId, alice)
        );
    }

    function test_itUpdatesTheBidDetails() public {
        // Call
        vm.prank(address(auctionHouse));
        uint256 returnedBidAmount = auctionModule.cancelBid(lotId, bidId, alice);

        // Check values
        LocalSealedBidBatchAuction.EncryptedBid memory encryptedBid =
            auctionModule.getBidData(lotId, bidId);
        assertEq(encryptedBid.bidder, alice);
        assertEq(encryptedBid.recipient, recipient);
        assertEq(encryptedBid.referrer, referrer);
        assertEq(encryptedBid.amount, bidAmount);
        assertEq(encryptedBid.encryptedAmountOut, auctionData);
        assertEq(uint8(encryptedBid.status), uint8(LocalSealedBidBatchAuction.BidStatus.Cancelled));

        // Check return value
        assertEq(returnedBidAmount, bidAmount);
    }
}
