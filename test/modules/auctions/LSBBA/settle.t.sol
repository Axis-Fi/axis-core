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
import {Bid as QueueBid} from "src/modules/auctions/LSBBA/MaxPriorityQueue.sol";

import {console2} from "forge-std/console2.sol";

contract LSBBASettleTest is Test, Permit2User {
    address internal constant _PROTOCOL = address(0x1);
    address internal alice = address(0x2);
    address internal constant recipient = address(0x3);
    address internal constant referrer = address(0x4);

    AuctionHouse internal auctionHouse;
    LocalSealedBidBatchAuction internal auctionModule;

    uint256 internal constant LOT_CAPACITY = 10e18;
    uint256 internal constant MINIMUM_PRICE = 1e18;

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

    uint256 internal constant SCALE = 1e18; // Constants are kept in this scale

    bytes32 internal bidSeed = bytes32(uint256(1e9));
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
    uint96 internal bidFive;
    uint256 internal bidFiveAmount = 6e18;
    uint256 internal bidFiveAmountOut = 5e18; // Price = 1.2
    LocalSealedBidBatchAuction.Decrypt internal decryptedBidFive;
    LocalSealedBidBatchAuction.Decrypt[] internal decrypts;

    uint8 internal quoteTokenDecimals = 18;
    uint8 internal baseTokenDecimals = 18;

    Auction.AuctionParams auctionParams;
    LocalSealedBidBatchAuction.AuctionDataParams auctionDataParams;

    function setUp() public {
        // Ensure the block timestamp is a sane value
        vm.warp(1_000_000);

        // Set up and install the auction module
        auctionHouse = new AuctionHouse(_PROTOCOL, _PERMIT2_ADDRESS);
        auctionModule = new LocalSealedBidBatchAuction(address(auctionHouse));
        auctionHouse.installModule(auctionModule);

        // Set auction data parameters
        auctionDataParams = LocalSealedBidBatchAuction.AuctionDataParams({
            minFillPercent: 25_000, // 25% = 2.5e18
            minBidPercent: 1000,
            minimumPrice: MINIMUM_PRICE,
            publicKeyModulus: PUBLIC_KEY_MODULUS
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
        auctionModule.auction(lotId, auctionParams, quoteTokenDecimals, baseTokenDecimals);

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
            abi.encodePacked(uint2str(lotId)),
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

    /// @notice     Calculates the marginal price, given the amount in and out
    ///
    /// @param      bidAmount_      The amount of the bid
    /// @param      bidAmountOut_   The amount of the bid out
    /// @return     uint256         The marginal price (18 dp)
    function _getMarginalPriceScaled(
        uint256 bidAmount_,
        uint256 bidAmountOut_
    ) internal view returns (uint256) {
        // Adjust all amounts to the scale
        uint256 bidAmountScaled = bidAmount_ * SCALE / 10 ** quoteTokenDecimals;
        uint256 bidAmountOutScaled = bidAmountOut_ * SCALE / 10 ** baseTokenDecimals;

        return bidAmountScaled * SCALE / bidAmountOutScaled;
    }

    /// @notice     Calculates the amount out, given the amount in and the marginal price
    ///
    /// @param      amountIn_               The amount in
    /// @param      marginalPriceScaled_    The marginal price (in terms of SCALE)
    /// @return     uint256                 The amount out (in native decimals)
    function _getAmountOut(
        uint256 amountIn_,
        uint256 marginalPriceScaled_
    ) internal view returns (uint256) {
        uint256 amountOutScaled = amountIn_ * SCALE / marginalPriceScaled_;
        return amountOutScaled * 10 ** baseTokenDecimals / 10 ** quoteTokenDecimals;
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

    modifier givenLotHasDecimals(uint8 quoteTokenDecimals_, uint8 baseTokenDecimals_) {
        quoteTokenDecimals = quoteTokenDecimals_;
        baseTokenDecimals = baseTokenDecimals_;

        // Adjust bid amounts
        bidOneAmount = bidOneAmount * 10 ** quoteTokenDecimals_ / SCALE;
        bidOneAmountOut = bidOneAmountOut * 10 ** baseTokenDecimals_ / SCALE;
        bidTwoAmount = bidTwoAmount * 10 ** quoteTokenDecimals_ / SCALE;
        bidTwoAmountOut = bidTwoAmountOut * 10 ** baseTokenDecimals_ / SCALE;
        bidThreeAmount = bidThreeAmount * 10 ** quoteTokenDecimals_ / SCALE;
        bidThreeAmountOut = bidThreeAmountOut * 10 ** baseTokenDecimals_ / SCALE;
        bidFourAmount = bidFourAmount * 10 ** quoteTokenDecimals_ / SCALE;
        bidFourAmountOut = bidFourAmountOut * 10 ** baseTokenDecimals_ / SCALE;
        bidFiveAmount = bidFiveAmount * 10 ** quoteTokenDecimals_ / SCALE;
        bidFiveAmountOut = bidFiveAmountOut * 10 ** baseTokenDecimals_ / SCALE;

        // Update auction implementation params
        auctionDataParams.minimumPrice = MINIMUM_PRICE * 10 ** quoteTokenDecimals_ / SCALE;

        // Update auction params
        auctionParams.capacity = LOT_CAPACITY * 10 ** baseTokenDecimals_ / SCALE; // Always base token
        auctionParams.implParams = abi.encode(auctionDataParams);
        lotId = 2;

        // Create a new lot with the decimals set
        vm.prank(address(auctionHouse));
        auctionModule.auction(lotId, auctionParams, quoteTokenDecimals, baseTokenDecimals);

        // Warp to the start of the auction
        vm.warp(lotStart);
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
        // Marginal price 1
        // Smallest bid (2) will not be filled at all
        (bidOne, decryptedBidOne) = _createBid(bidOneAmount, bidOneAmountOut);
        (bidTwo, decryptedBidTwo) = _createBid(bidTwoAmount, bidTwoAmountOut);
        (bidThree, decryptedBidThree) = _createBid(bidThreeAmount, bidThreeAmountOut);

        // Set up the decrypts array
        decrypts.push(decryptedBidOne);
        decrypts.push(decryptedBidTwo);
        decrypts.push(decryptedBidThree);
        _;
    }

    modifier whenLotIsOverSubscribedPartialFill() {
        // 2 + 3 + 6 > 10
        // Marginal price 1
        // Smallest bid (2) will be partially filled
        (bidOne, decryptedBidOne) = _createBid(bidOneAmount, bidOneAmountOut);
        (bidTwo, decryptedBidTwo) = _createBid(bidTwoAmount, bidTwoAmountOut);
        (bidFive, decryptedBidFive) = _createBid(bidFiveAmount, bidFiveAmountOut);

        // Set up the decrypts array
        decrypts.push(decryptedBidOne);
        decrypts.push(decryptedBidTwo);
        decrypts.push(decryptedBidFive);
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

    modifier whenHasBidBelowMinimum() {
        // Above minimum price
        // Not over capacity
        (bidOne, decryptedBidOne) = _createBid(bidOneAmount, bidOneAmountOut);
        (bidTwo, decryptedBidTwo) = _createBid(bidTwoAmount, bidTwoAmountOut);
        // < minimum
        (bidThree, decryptedBidThree) = _createBid(1e16, 1e16);

        // Set up the decrypts array
        decrypts.push(decryptedBidOne);
        decrypts.push(decryptedBidTwo);
        decrypts.push(decryptedBidThree);
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
    // [X] given the lot is over-subscribed with a partial fill
    //   [X] it returns winning bids, with the marginal price is the price at which the lot capacity is exhausted, and a partial fill for the lowest winning bid
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

    function test_whenLotIsBelowMinimumFilled()
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

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, 0); // Base tokens sold
        assertEq(lot.purchased, 0); // Quote tokens purchased
    }

    function test_whenLotIsBelowMinimumFilled_quoteTokenDecimalsLarger()
        public
        givenLotHasDecimals(17, 13)
        whenLotIsBelowMinimumFilled
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Expect no winning bids
        assertEq(winningBids.length, 0);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, 0); // Base tokens sold
        assertEq(lot.purchased, 0); // Quote tokens purchased
    }

    function test_whenLotIsBelowMinimumFilled_quoteTokenDecimalsSmaller()
        public
        givenLotHasDecimals(13, 17)
        whenLotIsBelowMinimumFilled
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Expect no winning bids
        assertEq(winningBids.length, 0);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, 0); // Base tokens sold
        assertEq(lot.purchased, 0); // Quote tokens purchased
    }

    function test_whenMarginalPriceBelowMinimum()
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

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, 0); // Base tokens sold
        assertEq(lot.purchased, 0); // Quote tokens purchased
    }

    function test_whenMarginalPriceBelowMinimum_quoteTokenDecimalsLarger()
        public
        givenLotHasDecimals(17, 13)
        whenMarginalPriceBelowMinimum
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Expect no winning bids
        assertEq(winningBids.length, 0);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, 0); // Base tokens sold
        assertEq(lot.purchased, 0); // Quote tokens purchased
    }

    function test_whenMarginalPriceBelowMinimum_quoteTokenDecimalsSmaller()
        public
        givenLotHasDecimals(13, 17)
        whenMarginalPriceBelowMinimum
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Expect no winning bids
        assertEq(winningBids.length, 0);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, 0); // Base tokens sold
        assertEq(lot.purchased, 0); // Quote tokens purchased
    }

    function test_whenBidSizeIsBelowMinimum()
        public
        whenHasBidBelowMinimum
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidTwoAmount);
        assertEq(winningBids[0].minAmountOut, bidTwoAmountOut);

        // Second bid
        assertEq(winningBids[1].amount, bidOneAmount);
        assertEq(winningBids[1].minAmountOut, bidOneAmountOut);

        // Third bid does not meet minimum

        assertEq(winningBids.length, 2);
    }

    function test_whenLotIsOverSubscribed()
        public
        whenLotIsOverSubscribed
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = _getMarginalPriceScaled(bidTwoAmount, bidTwoAmountOut);

        bidThreeAmountOut = _getAmountOut(bidThreeAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidThreeAmount);
        assertEq(winningBids[0].minAmountOut, bidThreeAmountOut);

        // Second bid
        assertEq(winningBids[1].amount, bidTwoAmount);
        assertEq(winningBids[1].minAmountOut, bidTwoAmountOut);

        // Expect winning bids
        assertEq(winningBids.length, 2);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidThreeAmountOut + bidTwoAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidThreeAmount + bidTwoAmount); // Quote tokens purchased
    }

    function test_whenLotIsOverSubscribed_quoteTokenDecimalsLarger()
        public
        givenLotHasDecimals(17, 13)
        whenLotIsOverSubscribed
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = _getMarginalPriceScaled(bidTwoAmount, bidTwoAmountOut);

        bidThreeAmountOut = _getAmountOut(bidThreeAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidThreeAmount);
        assertEq(winningBids[0].minAmountOut, bidThreeAmountOut);

        // Second bid
        assertEq(winningBids[1].amount, bidTwoAmount);
        assertEq(winningBids[1].minAmountOut, bidTwoAmountOut);

        // Expect winning bids
        assertEq(winningBids.length, 2);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidThreeAmountOut + bidTwoAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidThreeAmount + bidTwoAmount); // Quote tokens purchased
    }

    function test_whenLotIsOverSubscribed_quoteTokenDecimalsSmaller()
        public
        givenLotHasDecimals(13, 17)
        whenLotIsOverSubscribed
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = _getMarginalPriceScaled(bidTwoAmount, bidTwoAmountOut);

        bidThreeAmountOut = _getAmountOut(bidThreeAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidThreeAmount);
        assertEq(winningBids[0].minAmountOut, bidThreeAmountOut);

        // Second bid
        assertEq(winningBids[1].amount, bidTwoAmount);
        assertEq(winningBids[1].minAmountOut, bidTwoAmountOut);

        // Expect winning bids
        assertEq(winningBids.length, 2);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidThreeAmountOut + bidTwoAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidThreeAmount + bidTwoAmount); // Quote tokens purchased
    }

    function test_whenLotIsOverSubscribed_partialFill()
        public
        whenLotIsOverSubscribedPartialFill
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = _getMarginalPriceScaled(bidTwoAmount, bidTwoAmountOut);

        bidThreeAmountOut = _getAmountOut(bidThreeAmount, marginalPrice);
        bidFiveAmountOut = _getAmountOut(bidFiveAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidFiveAmount, "bid 1: amount mismatch");
        assertEq(winningBids[0].minAmountOut, bidFiveAmountOut, "bid 1: minAmountOut mismatch");

        // Second bid
        assertEq(winningBids[1].amount, bidTwoAmount, "bid 2: amount mismatch");
        assertEq(winningBids[1].minAmountOut, bidTwoAmountOut, "bid 2: minAmountOut mismatch");

        // Third bid - will be a partial fill and recognised by the AuctionHouse
        assertEq(winningBids[2].amount, bidOneAmount, "bid 3: amount mismatch");
        assertEq(winningBids[2].minAmountOut, bidOneAmountOut, "bid 3: minAmountOut mismatch");

        // Expect winning bids
        assertEq(winningBids.length, 3);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidFiveAmountOut + bidTwoAmountOut + bidOneAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidFiveAmount + bidTwoAmount + bidOneAmount); // Quote tokens purchased
    }

    function test_whenLotIsOverSubscribed_partialFill_quoteTokenDecimalsLarger()
        public
        givenLotHasDecimals(17, 13)
        whenLotIsOverSubscribedPartialFill
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = _getMarginalPriceScaled(bidTwoAmount, bidTwoAmountOut);

        bidThreeAmountOut = _getAmountOut(bidThreeAmount, marginalPrice);
        bidFiveAmountOut = _getAmountOut(bidFiveAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidFiveAmount, "bid 1: amount mismatch");
        assertEq(winningBids[0].minAmountOut, bidFiveAmountOut, "bid 1: minAmountOut mismatch");

        // Second bid
        assertEq(winningBids[1].amount, bidTwoAmount, "bid 2: amount mismatch");
        assertEq(winningBids[1].minAmountOut, bidTwoAmountOut, "bid 2: minAmountOut mismatch");

        // Third bid - will be a partial fill and recognised by the AuctionHouse
        assertEq(winningBids[2].amount, bidOneAmount, "bid 3: amount mismatch");
        assertEq(winningBids[2].minAmountOut, bidOneAmountOut, "bid 3: minAmountOut mismatch");

        // Expect winning bids
        assertEq(winningBids.length, 3);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidFiveAmountOut + bidTwoAmountOut + bidOneAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidFiveAmount + bidTwoAmount + bidOneAmount); // Quote tokens purchased
    }

    function test_whenLotIsOverSubscribed_partialFill_quoteTokenDecimalsSmaller()
        public
        givenLotHasDecimals(13, 17)
        whenLotIsOverSubscribedPartialFill
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = _getMarginalPriceScaled(bidTwoAmount, bidTwoAmountOut);

        bidThreeAmountOut = _getAmountOut(bidThreeAmount, marginalPrice);
        bidFiveAmountOut = _getAmountOut(bidFiveAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidFiveAmount, "bid 1: amount mismatch");
        assertEq(winningBids[0].minAmountOut, bidFiveAmountOut, "bid 1: minAmountOut mismatch");

        // Second bid
        assertEq(winningBids[1].amount, bidTwoAmount, "bid 2: amount mismatch");
        assertEq(winningBids[1].minAmountOut, bidTwoAmountOut, "bid 2: minAmountOut mismatch");

        // Third bid - will be a partial fill and recognised by the AuctionHouse
        assertEq(winningBids[2].amount, bidOneAmount, "bid 3: amount mismatch");
        assertEq(winningBids[2].minAmountOut, bidOneAmountOut, "bid 3: minAmountOut mismatch");

        // Expect winning bids
        assertEq(winningBids.length, 3);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidFiveAmountOut + bidTwoAmountOut + bidOneAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidFiveAmount + bidTwoAmount + bidOneAmount); // Quote tokens purchased
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
        uint256 marginalPrice = _getMarginalPriceScaled(bidOneAmount, bidOneAmountOut);

        bidTwoAmountOut = _getAmountOut(bidTwoAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidTwoAmount);
        assertEq(winningBids[0].minAmountOut, bidTwoAmountOut);

        // Second bid
        assertEq(winningBids[1].amount, bidOneAmount);
        assertEq(winningBids[1].minAmountOut, bidOneAmountOut);

        // Expect winning bids
        assertEq(winningBids.length, 2);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidTwoAmountOut + bidOneAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidTwoAmount + bidOneAmount); // Quote tokens purchased
    }

    function test_whenLotIsFilled_quoteTokenDecimalsLarger()
        public
        givenLotHasDecimals(17, 13)
        whenLotIsFilled
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = _getMarginalPriceScaled(bidOneAmount, bidOneAmountOut);

        bidTwoAmountOut = _getAmountOut(bidTwoAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidTwoAmount, "bid 1: amount mismatch");
        assertEq(winningBids[0].minAmountOut, bidTwoAmountOut, "bid 1: minAmountOut mismatch");

        // Second bid
        assertEq(winningBids[1].amount, bidOneAmount, "bid 2: amount mismatch");
        assertEq(winningBids[1].minAmountOut, bidOneAmountOut, "bid 2: minAmountOut mismatch");

        // Expect winning bids
        assertEq(winningBids.length, 2, "winning bids length mismatch");

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidTwoAmountOut + bidOneAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidTwoAmount + bidOneAmount); // Quote tokens purchased
    }

    function test_whenLotIsFilled_quoteTokenDecimalsSmaller()
        public
        givenLotHasDecimals(13, 17)
        whenLotIsFilled
        whenLotHasConcluded
        whenLotDecryptionIsComplete
    {
        // Call for settlement
        vm.prank(address(auctionHouse));
        (LocalSealedBidBatchAuction.Bid[] memory winningBids,) = auctionModule.settle(lotId);

        // Calculate the marginal price
        uint256 marginalPrice = _getMarginalPriceScaled(bidOneAmount, bidOneAmountOut);

        bidTwoAmountOut = _getAmountOut(bidTwoAmount, marginalPrice);

        // First bid - largest amount out
        assertEq(winningBids[0].amount, bidTwoAmount);
        assertEq(winningBids[0].minAmountOut, bidTwoAmountOut);

        // Second bid
        assertEq(winningBids[1].amount, bidOneAmount);
        assertEq(winningBids[1].minAmountOut, bidOneAmountOut);

        // Expect winning bids
        assertEq(winningBids.length, 2);

        // Lot is updated
        Auction.Lot memory lot = auctionModule.getLot(lotId);
        assertEq(lot.capacity, 0); // Set to 0 to prevent further bids
        assertEq(lot.sold, bidTwoAmountOut + bidOneAmountOut); // Base tokens sold
        assertEq(lot.purchased, bidTwoAmount + bidOneAmount); // Quote tokens purchased
    }
}
