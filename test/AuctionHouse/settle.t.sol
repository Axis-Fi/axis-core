// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {AuctionHouse, Router} from "src/AuctionHouse.sol";
import {Auction, AuctionModule} from "src/modules/Auction.sol";
import {IHooks, IAllowlist, Auctioneer} from "src/bases/Auctioneer.sol";
import {RSAOAEP} from "src/lib/RSA.sol";
import {LocalSealedBidBatchAuction} from "src/modules/auctions/LSBBA/LSBBA.sol";

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

contract SettleTest is Test, Permit2User {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;

    AuctionHouse internal auctionHouse;
    LocalSealedBidBatchAuction internal auctionModule;

    uint96 internal lotId;
    uint48 internal lotStart;
    uint48 internal auctionDuration = 1 days;
    uint48 internal lotConclusion;
    bytes internal constant PUBLIC_KEY_MODULUS = abi.encodePacked(
        bytes32(0xB925394F570C7C765F121826DFC8A1661921923B33408EFF62DCAC0D263952FE),
        bytes32(0x158C12B2B35525F7568CB8DC7731FBC3739F22D94CB80C5622E788DB4532BD8C),
        bytes32(0x8643680DA8C00A5E7C967D9D087AA1380AE9A031AC292C971EC75F9BD3296AE1),
        bytes32(0x1AFCC05BD15602738CBE9BD75B76403AB2C9409F2CC0C189B4551DEE8B576AD3)
    );

    address internal immutable protocol = address(0x2);
    address internal immutable referrer = address(0x4);
    address internal immutable auctionOwner = address(0x5);
    address internal immutable recipient = address(0x6);
    address internal immutable bidderOne = address(0x7);
    address internal immutable bidderTwo = address(0x8);

    uint48 internal constant protocolFee = 1000; // 1%
    uint48 internal constant referrerFee = 500; // 0.5%

    uint256 internal constant LOT_CAPACITY = 10e18;
    uint256 internal bidSeed = 1e9;

    uint256 internal constant bidOneAmount = 4e18;
    uint256 internal constant bidOneAmountOut = 4e18; // Price = 1
    uint256 internal constant bidTwoAmount = 6e18;
    uint256 internal constant bidTwoAmountOut = 6e18; // Price = 1
    uint256 internal constant bidThreeAmount = 7e18;
    uint256 internal constant bidThreeAmountOut = 7e18; // Price = 1
    uint256 internal constant bidFourAmount = 8e18;
    uint256 internal constant bidFourAmountOut = 2e18; // Price = 4
    uint256 internal constant bidFiveAmount = 8e18;
    uint256 internal constant bidFiveAmountOut = 4e18; // Price = 2

    function setUp() external {
        // Set block timestamp
        vm.warp(1_000_000);

        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(protocol, _PERMIT2_ADDRESS);
        auctionModule = new LocalSealedBidBatchAuction(address(auctionHouse));
        auctionHouse.installModule(auctionModule);

        // Set fees
        auctionHouse.setProtocolFee(protocolFee);
        auctionHouse.setReferrerFee(referrer, referrerFee);

        // Auction parameters
        LocalSealedBidBatchAuction.AuctionDataParams memory auctionDataParams =
        LocalSealedBidBatchAuction.AuctionDataParams({
            minFillPercent: 1000, // 1%
            minBidPercent: 1000, // 1%
            minimumPrice: 5e17, // 0.5e18
            publicKeyModulus: PUBLIC_KEY_MODULUS
        });

        lotStart = uint48(block.timestamp) + 1;
        Auction.AuctionParams memory auctionParams = Auction.AuctionParams({
            start: lotStart,
            duration: auctionDuration,
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode(auctionDataParams)
        });
        lotConclusion = auctionParams.start + auctionParams.duration;

        (Keycode moduleKeycode,) = unwrapVeecode(auctionModule.VEECODE());
        Auctioneer.RoutingParams memory routingParams = Auctioneer.RoutingParams({
            auctionType: moduleKeycode,
            baseToken: baseToken,
            quoteToken: quoteToken,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            payoutData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode("")
        });

        // Set up pre-funding
        baseToken.mint(auctionOwner, LOT_CAPACITY);
        vm.prank(auctionOwner);
        baseToken.approve(address(auctionHouse), LOT_CAPACITY);

        // Create an auction lot
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
    }

    function _createBid(
        address bidder_,
        uint256 bidAmount_,
        uint256 bidAmountOut_
    ) internal returns (uint96 bidId_, LocalSealedBidBatchAuction.Decrypt memory decryptedBid) {
        // Encrypt the bid amount
        decryptedBid = LocalSealedBidBatchAuction.Decrypt({amountOut: bidAmountOut_, seed: bidSeed});
        bytes memory auctionData_ = _encrypt(decryptedBid);

        Router.BidParams memory bidParams = Router.BidParams({
            lotId: lotId,
            recipient: recipient,
            referrer: referrer,
            amount: bidAmount_,
            auctionData: auctionData_,
            allowlistProof: bytes(""),
            permit2Data: bytes("")
        });

        // Create a bid
        vm.prank(bidder_);
        uint96 bidId = auctionHouse.bid(bidParams);

        return (bidId, decryptedBid);
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

    // ======== Modifiers ======== //

    LocalSealedBidBatchAuction.Decrypt[] internal decryptedBids;
    uint256 internal marginalPrice;

    modifier givenLotHasSufficientBids() {
        // Mint quote tokens to the bidders
        quoteToken.mint(bidderOne, bidOneAmount);
        quoteToken.mint(bidderTwo, bidTwoAmount);

        // Authorise spending
        vm.prank(bidderOne);
        quoteToken.approve(address(auctionHouse), bidOneAmount);
        vm.prank(bidderTwo);
        quoteToken.approve(address(auctionHouse), bidTwoAmount);

        // Create bids
        // 4 + 6 = 10
        (, LocalSealedBidBatchAuction.Decrypt memory decryptedBidOne) =
            _createBid(bidderOne, bidOneAmount, bidOneAmountOut);
        (, LocalSealedBidBatchAuction.Decrypt memory decryptedBidTwo) =
            _createBid(bidderTwo, bidTwoAmount, bidTwoAmountOut);
        decryptedBids.push(decryptedBidOne);
        decryptedBids.push(decryptedBidTwo);

        marginalPrice = bidTwoAmount * 1e18 / bidTwoAmountOut;
        _;
    }

    modifier givenLotHasPartialFill() {
        // Mint quote tokens to the bidders
        quoteToken.mint(bidderOne, bidOneAmount);
        quoteToken.mint(bidderTwo, bidThreeAmount);

        // Authorise spending
        vm.prank(bidderOne);
        quoteToken.approve(address(auctionHouse), bidOneAmount);
        vm.prank(bidderTwo);
        quoteToken.approve(address(auctionHouse), bidThreeAmount);

        // Create bids
        // 4 + 7 = 11 (over-subscribed)
        (, LocalSealedBidBatchAuction.Decrypt memory decryptedBidOne) =
            _createBid(bidderOne, bidOneAmount, bidOneAmountOut);
        (, LocalSealedBidBatchAuction.Decrypt memory decryptedBidThree) =
            _createBid(bidderTwo, bidThreeAmount, bidThreeAmountOut);
        decryptedBids.push(decryptedBidOne);
        decryptedBids.push(decryptedBidThree);

        marginalPrice = bidThreeAmount * 1e18 / bidThreeAmountOut;
        _;
    }

    modifier givenLotHasSufficientBids_differentMarginalPrice() {
        // Mint quote tokens to the bidders
        quoteToken.mint(bidderOne, bidFourAmount);
        quoteToken.mint(bidderTwo, bidFiveAmount);

        // Authorise spending
        vm.prank(bidderOne);
        quoteToken.approve(address(auctionHouse), bidFourAmount);
        vm.prank(bidderTwo);
        quoteToken.approve(address(auctionHouse), bidFiveAmount);

        // Create bids
        // 4 + 2 = 6
        (, LocalSealedBidBatchAuction.Decrypt memory decryptedBidOne) =
            _createBid(bidderOne, bidFourAmount, bidFourAmountOut);
        (, LocalSealedBidBatchAuction.Decrypt memory decryptedBidTwo) =
            _createBid(bidderTwo, bidFiveAmount, bidFiveAmountOut);
        decryptedBids.push(decryptedBidOne);
        decryptedBids.push(decryptedBidTwo);

        // bidFour first (price = 4), then bidFive (price = 3)
        marginalPrice = bidFiveAmount * 1e18 / bidFiveAmountOut;
        _;
    }

    modifier givenLotIdIsInvalid() {
        lotId = 255;
        _;
    }

    modifier givenLotHasStarted() {
        // Warp to the start of the auction
        vm.warp(lotStart);
        _;
    }

    modifier givenAuctionModuleReverts() {
        // Cancel the auction
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);
        _;
    }

    modifier givenLotHasConcluded() {
        // Warp to the end of the auction
        vm.warp(lotConclusion + 1);
        _;
    }

    modifier givenLotHasDecrypted() {
        // Decrypt the bids
        auctionModule.decryptAndSortBids(lotId, decryptedBids);
        _;
    }

    modifier givenAuctionHouseHasInsufficientQuoteTokenBalance() {
        // Approve spending
        vm.prank(address(auctionHouse));
        quoteToken.approve(address(this), quoteToken.balanceOf(address(auctionHouse)));

        // Burn quote tokens
        quoteToken.burn(address(auctionHouse), quoteToken.balanceOf(address(auctionHouse)));
        _;
    }

    modifier givenAuctionHouseHasInsufficientBaseTokenBalance() {
        // Approve spending
        vm.prank(address(auctionHouse));
        baseToken.approve(address(this), baseToken.balanceOf(address(auctionHouse)));

        // Burn base tokens
        baseToken.burn(address(auctionHouse), baseToken.balanceOf(address(auctionHouse)));
        _;
    }

    // ======== Tests ======== //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [ ] when the caller is not authorized to settle
    //  [ ] it reverts
    // [X] when the auction module reverts
    //  [X] it reverts
    // [X] given the auction house has insufficient balance of the quote token
    //  [X] it reverts
    // [X] given the auction house has insufficient balance of the base token
    //  [X] it reverts
    // [ ] given that the capacity is not filled
    //  [ ] it succeeds - transfers remaining base tokens back to the owner
    // [X] given the last bidder has a partial fill
    //  [X] it succeeds - last bidder receives the partial fill and is returned excess quote tokens
    // [X] given the auction bids have different prices
    //  [X] it succeeds
    // [ ] given that the quote token decimals differ from the base token decimals
    //  [ ] it succeeds
    // [X] it succeeds - auction owner receives quote tokens (minus fees), bidders receive base tokens and fees accrued

    function test_invalidLotId() external givenLotIdIsInvalid givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Attempt to settle the lot
        auctionHouse.settle(lotId);
    }

    function test_auctionModuleReverts_reverts() external givenAuctionModuleReverts {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LocalSealedBidBatchAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Attempt to settle the lot
        auctionHouse.settle(lotId);
    }

    function test_insufficientQuoteToken_reverts()
        external
        givenLotHasStarted
        givenLotHasSufficientBids
        givenLotHasConcluded
        givenLotHasDecrypted
        givenAuctionHouseHasInsufficientQuoteTokenBalance
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FAILED");

        // Attempt to settle the lot
        auctionHouse.settle(lotId);
    }

    function test_insufficientBaseTokenBalance_reverts()
        external
        givenLotHasStarted
        givenLotHasSufficientBids
        givenLotHasConcluded
        givenLotHasDecrypted
        givenAuctionHouseHasInsufficientBaseTokenBalance
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FAILED");

        // Attempt to settle the lot
        auctionHouse.settle(lotId);
    }

    function test_success()
        external
        givenLotHasStarted
        givenLotHasSufficientBids
        givenLotHasConcluded
        givenLotHasDecrypted
    {
        // Attempt to settle the lot
        auctionHouse.settle(lotId);

        // Check base token balances
        assertEq(
            baseToken.balanceOf(bidderOne),
            bidOneAmountOut,
            "bidderOne: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(bidderTwo),
            bidTwoAmountOut,
            "bidderTwo: incorrect balance of base token"
        );

        // Check quote token balances
        assertEq(quoteToken.balanceOf(bidderOne), 0, "bidderOne: incorrect balance of quote token");
        assertEq(quoteToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of quote token");

        // Calculate fees on quote tokens
        uint256 protocolFeeAmount = (bidOneAmount + bidTwoAmount) * protocolFee / 1e5;
        uint256 referrerFeeAmount = (bidOneAmount + bidTwoAmount) * referrerFee / 1e5;
        uint256 totalFeeAmount = protocolFeeAmount + referrerFeeAmount;

        // Auction owner should have received quote tokens minus fees
        assertEq(
            quoteToken.balanceOf(auctionOwner),
            bidOneAmount + bidTwoAmount - totalFeeAmount,
            "auction owner: incorrect balance of quote token"
        );

        // Fees stored on auction house
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)),
            totalFeeAmount,
            "auction house: incorrect balance of quote token"
        );

        // Fee records updated
        assertEq(
            auctionHouse.rewards(protocol, quoteToken), protocolFeeAmount, "incorrect protocol fees"
        );
        assertEq(
            auctionHouse.rewards(referrer, quoteToken), referrerFeeAmount, "incorrect referrer fees"
        );
    }

    function test_partialFill()
        external
        givenLotHasStarted
        givenLotHasPartialFill
        givenLotHasConcluded
        givenLotHasDecrypted
    {
        // Attempt to settle the lot
        auctionHouse.settle(lotId);

        // Check base token balances
        uint256 bidOneAmountOutActual = 3e18;
        assertEq(
            baseToken.balanceOf(bidderOne),
            bidOneAmountOutActual,
            "bidderOne: incorrect balance of base token"
        ); // Received partial payout. 10 - 7 = 3
        assertEq(
            baseToken.balanceOf(bidderTwo),
            bidThreeAmountOut,
            "bidderTwo: incorrect balance of base token"
        );

        // Check quote token balances
        uint256 bidOnePercentageFilled = bidOneAmountOutActual * 1e18 / bidOneAmountOut;
        uint256 bidOneAmountActual = bidOneAmount * bidOnePercentageFilled / 1e18;
        assertEq(
            quoteToken.balanceOf(bidderOne),
            bidOneAmount - bidOneAmountActual,
            "bidderOne: incorrect balance of quote token"
        ); // Remainder received as quote tokens.
        assertEq(quoteToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of quote token");

        // Calculate fees on quote tokens
        uint256 protocolFeeAmount = (bidOneAmountActual + bidThreeAmount) * protocolFee / 1e5;
        uint256 referrerFeeAmount = (bidOneAmountActual + bidThreeAmount) * referrerFee / 1e5;
        uint256 totalFeeAmount = protocolFeeAmount + referrerFeeAmount;

        // Auction owner should have received quote tokens minus fees
        assertEq(
            quoteToken.balanceOf(auctionOwner),
            bidOneAmountActual + bidThreeAmount - totalFeeAmount,
            "auction owner: incorrect balance of quote token"
        );

        // Fees stored on auction house
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)),
            totalFeeAmount,
            "auction house: incorrect balance of quote token"
        );

        // Fee records updated
        assertEq(
            auctionHouse.rewards(protocol, quoteToken), protocolFeeAmount, "incorrect protocol fees"
        );
        assertEq(
            auctionHouse.rewards(referrer, quoteToken), referrerFeeAmount, "incorrect referrer fees"
        );
    }

    function test_marginalPrice()
        external
        givenLotHasStarted
        givenLotHasSufficientBids_differentMarginalPrice
        givenLotHasConcluded
        givenLotHasDecrypted
    {
        // Attempt to settle the lot
        auctionHouse.settle(lotId);

        // Check base token balances
        uint256 bidFourAmountOutActual = bidFourAmount * 1e18 / marginalPrice;
        uint256 bidFiveAmountOutActual = bidFiveAmountOut; // since it set the marginal price
        assertEq(
            baseToken.balanceOf(bidderOne),
            bidFourAmountOutActual,
            "bidderOne: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(bidderTwo),
            bidFiveAmountOutActual,
            "bidderTwo: incorrect balance of base token"
        );

        // Check quote token balances
        assertEq(quoteToken.balanceOf(bidderOne), 0, "bidderOne: incorrect balance of quote token");
        assertEq(quoteToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of quote token");

        // Calculate fees on quote tokens
        uint256 protocolFeeAmount = (bidFourAmount + bidFiveAmount) * protocolFee / 1e5;
        uint256 referrerFeeAmount = (bidFourAmount + bidFiveAmount) * referrerFee / 1e5;
        uint256 totalFeeAmount = protocolFeeAmount + referrerFeeAmount;

        // Auction owner should have received quote tokens minus fees
        assertEq(
            quoteToken.balanceOf(auctionOwner),
            bidFourAmount + bidFiveAmount - totalFeeAmount,
            "auction owner: incorrect balance of quote token"
        );

        // Fees stored on auction house
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)),
            totalFeeAmount,
            "auction house: incorrect balance of quote token"
        );

        // Fee records updated
        assertEq(
            auctionHouse.rewards(protocol, quoteToken), protocolFeeAmount, "incorrect protocol fees"
        );
        assertEq(
            auctionHouse.rewards(referrer, quoteToken), referrerFeeAmount, "incorrect referrer fees"
        );
    }
}
