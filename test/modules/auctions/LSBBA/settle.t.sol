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
import {Bid as QueueBid} from "src/modules/auctions/LSBBA/MaxPriorityQueue.sol";

contract LSBBASettleTest is Test, Permit2User {
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

    // TODO adjust these
    uint256 internal bidSeed = 1e9;
    uint96 internal bidOne;
    uint256 internal bidOneAmount = 2e18;
    uint256 internal bidOneAmountOut = 2e18; // Price = 1
    LocalSealedBidBatchAuction.Decrypt internal decryptedBidOne;
    uint96 internal bidTwo;
    uint256 internal bidTwoAmount = 3e18;
    uint256 internal bidTwoAmountOut = 3e18; // Price = 1
    LocalSealedBidBatchAuction.Decrypt internal decryptedBidTwo;
    uint96 internal bidThree;
    uint256 internal bidThreeAmount = 7e18;
    uint256 internal bidThreeAmountOut = 7e18; // Price = 1
    LocalSealedBidBatchAuction.Decrypt internal decryptedBidThree;
    uint96 internal bidFour;
    uint256 internal bidFourAmount = 2e18;
    uint256 internal bidFourAmountOut = 4e18; // Price < 1e18 (minimum price)
    LocalSealedBidBatchAuction.Decrypt internal decryptedBidFour;
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
            minFillPercent: 25_000, // 25% = 2.5e18
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

    modifier whenLotIsBelowMinimumFilled() {
        // 2 < 2.5
        (bidOne, decryptedBidOne) = _createBid(bidOneAmount, bidOneAmountOut);

        // Set up the decrypts array
        decrypts.push(decryptedBidOne);
        _;
    }

    modifier whenLotIsOverSubscribed() {
        // 2 + 3 + 7 > 10
        (bidOne, decryptedBidOne) = _createBid(bidOneAmount, bidOneAmountOut);
        (bidTwo, decryptedBidTwo) = _createBid(bidTwoAmount, bidTwoAmountOut);
        (bidThree, decryptedBidThree) = _createBid(bidThreeAmount, bidThreeAmountOut);

        // Set up the decrypts array
        decrypts.push(decryptedBidOne);
        decrypts.push(decryptedBidTwo);
        decrypts.push(decryptedBidThree);
        _;
    }

    modifier whenMarginalPriceBelowMinimum() {
        // 2 + 2 > 2.5
        // Marginal price of 2/4 = 0.5 < 1
        (bidOne, decryptedBidOne) = _createBid(bidOneAmount, bidOneAmountOut);
        (bidFour, decryptedBidFour) = _createBid(bidFourAmount, bidFourAmountOut);

        // Set up the decrypts array
        decrypts.push(decryptedBidOne);
        decrypts.push(decryptedBidFour);
        _;
    }

    modifier whenLotIsFilled() {
        // 2 + 3 > 2.5
        // Above minimum price
        // Not over capacity
        (bidOne, decryptedBidOne) = _createBid(bidOneAmount, bidOneAmountOut);
        (bidTwo, decryptedBidTwo) = _createBid(bidTwoAmount, bidTwoAmountOut);

        // Set up the decrypts array
        decrypts.push(decryptedBidOne);
        decrypts.push(decryptedBidTwo);
        _;
    }

    modifier whenLotDecryptionIsComplete() {
        // Decrypt the bids
        auctionModule.decryptAndSortBids(lotId, decrypts);
        _;
    }

    modifier whenLotHasSettled() {
        // Call for settlement
        vm.prank(address(auctionHouse));
        auctionModule.settle(lotId);
        _;
    }

    // ===== Tests ===== //

    // [X] when the lot id is invalid
    //   [X] it reverts
    // [X] when the caller is not the parent
    //   [X] it reverts
    // [X] when execOnModule is used
    //   [X] it reverts
    // [X] when the lot has not concluded
    //   [X] it reverts
    // [X] when the lot has not been decrypted
    //   [X] it reverts
    // [X] when the lot has been settled already
    //   [X] it reverts
    // [X] when the filled amount is less than the lot minimum
    //   [X] it returns no winning bids
    // [X] when the marginal price is less than the minimum price
    //   [X] it returns no winning bids
    // [X] given the lot is over-subscribed
    //   [X] it returns winning bids, with the marginal price is the price at which the lot capacity is exhausted
    // [ ] given the lot is over-subscribed with a partial fill
    //   [ ] it returns winning bids, with the marginal price is the price at which the lot capacity is exhausted, and a partial fill for the lowest winning bid
    // [X] when the filled amount is greater than the lot minimum
    //   [X] it returns winning bids, with the marginal price is the minimum price

    function test_whenLotIdIsInvalid_reverts() public whenLotIdIsInvalid {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Call for settlement
        vm.prank(address(auctionHouse));
        auctionModule.settle(lotId);
    }

    function test_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call for settlement
        auctionModule.settle(lotId);
    }

    function test_execOnModule_reverts() public {
        Veecode moduleVeecode = auctionModule.VEECODE();

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleExecutionReverted.selector,
            abi.encodeWithSelector(Module.Module_OnlyInternal.selector)
        );
        vm.expectRevert(err);

        // Call for settlement
        auctionHouse.execOnModule(
            moduleVeecode, abi.encodeWithSelector(Auction.settle.selector, lotId)
        );
    }

    function test_whenLotHasNotConcluded_reverts() public whenLotHasNotConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketActive.selector, lotId);
        vm.expectRevert(err);

        // Call for settlement
        vm.prank(address(auctionHouse));
        auctionModule.settle(lotId);
    }

    function test_notDecrypted_reverts() public whenLotIsFilled whenLotHasConcluded {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call for settlement
        vm.prank(address(auctionHouse));
        auctionModule.settle(lotId);
    }

    function test_whenLotHasSettled_reverts()
        public
        whenLotIsFilled
        whenLotHasConcluded
        whenLotDecryptionIsComplete
        whenLotHasSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call for settlement
        vm.prank(address(auctionHouse));
        auctionModule.settle(lotId);
    }

    function test_whenLotIsBelowMinimumFilled_returnsNoWinningBids()
        public
        whenLotIsBelowMinimumFilled
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Expect no winning bids
        assertEq(winningBids.length, 0);
    }

    function test_whenMarginalPriceBelowMinimum_returnsNoWinningBids()
        public
        whenMarginalPriceBelowMinimum
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Expect no winning bids
        assertEq(winningBids.length, 0);
    }

    function test_whenLotIsOverSubscribed_returnsWinningBids()
        public
        whenLotIsOverSubscribed
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = bidTwoAmount * 1e18 / bidTwoAmountOut;

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidThreeAmount);
        assertEq(winningBids[0].minAmountOut, marginalPrice);

        // Second bid
        assertEq(winningBids[1].amount, bidTwoAmount);
        assertEq(winningBids[1].minAmountOut, marginalPrice);

        // Expect winning bids
        assertEq(winningBids.length, 2);
    }

    function test_whenLotIsFilled()
        public
        whenLotIsFilled
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = bidOneAmount * 1e18 / bidOneAmountOut;

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidTwoAmount);
        assertEq(winningBids[0].minAmountOut, marginalPrice);

        // Second bid
        assertEq(winningBids[1].amount, bidOneAmount);
        assertEq(winningBids[1].minAmountOut, marginalPrice);

        // Expect winning bids
        assertEq(winningBids.length, 2);
    }
}
