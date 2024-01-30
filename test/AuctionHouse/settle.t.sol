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

import {console2} from "forge-std/console2.sol";

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
    uint256 internal constant MINIMUM_PRICE = 5e17; // 0.5e18
    uint256 internal _lotCapacity = LOT_CAPACITY;
    uint256 internal constant SCALE = 1e18;
    uint256 internal constant BID_SEED = 1e9;

    uint256 internal bidOneAmount = 4e18;
    uint256 internal bidOneAmountOut = 4e18; // Price = 1
    uint256 internal bidTwoAmount = 6e18;
    uint256 internal bidTwoAmountOut = 6e18; // Price = 1
    uint256 internal bidThreeAmount = 7e18;
    uint256 internal bidThreeAmountOut = 7e18; // Price = 1
    uint256 internal bidFourAmount = 8e18;
    uint256 internal bidFourAmountOut = 2e18; // Price = 4
    uint256 internal bidFiveAmount = 8e18;
    uint256 internal bidFiveAmountOut = 4e18; // Price = 2

    uint8 internal quoteTokenDecimals = 18;
    uint8 internal baseTokenDecimals = 18;

    Auction.AuctionParams internal auctionParams;
    Auctioneer.RoutingParams internal routingParams;
    LocalSealedBidBatchAuction.AuctionDataParams internal auctionDataParams;

    function setUp() external {
        // Set block timestamp
        vm.warp(1_000_000);

        baseToken = new MockERC20("Base Token", "BASE", baseTokenDecimals);
        quoteToken = new MockERC20("Quote Token", "QUOTE", quoteTokenDecimals);

        auctionHouse = new AuctionHouse(protocol, _PERMIT2_ADDRESS);
        auctionModule = new LocalSealedBidBatchAuction(address(auctionHouse));
        auctionHouse.installModule(auctionModule);

        // Set fees
        auctionHouse.setProtocolFee(protocolFee);
        auctionHouse.setReferrerFee(referrer, referrerFee);

        // Auction parameters
        auctionDataParams = LocalSealedBidBatchAuction.AuctionDataParams({
            minFillPercent: 1000, // 1%
            minBidPercent: 1000, // 1%
            minimumPrice: MINIMUM_PRICE,
            publicKeyModulus: PUBLIC_KEY_MODULUS
        });

        lotStart = uint48(block.timestamp) + 1;
        auctionParams = Auction.AuctionParams({
            start: lotStart,
            duration: auctionDuration,
            capacityInQuote: false,
            capacity: _lotCapacity,
            implParams: abi.encode(auctionDataParams)
        });
        lotConclusion = auctionParams.start + auctionParams.duration;

        (Keycode moduleKeycode,) = unwrapVeecode(auctionModule.VEECODE());
        routingParams = Auctioneer.RoutingParams({
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
        baseToken.mint(auctionOwner, _lotCapacity);
        vm.prank(auctionOwner);
        baseToken.approve(address(auctionHouse), _lotCapacity);

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
        decryptedBid =
            LocalSealedBidBatchAuction.Decrypt({amountOut: bidAmountOut_, seed: BID_SEED});
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

    function _getAmountOut(
        uint256 amountIn_,
        uint256 marginalPrice_
    ) internal view returns (uint256) {
        uint256 amountOutScaled = amountIn_ * SCALE / marginalPrice_;
        return amountOutScaled * 10 ** baseTokenDecimals / 10 ** quoteTokenDecimals;
    }

    // ======== Modifiers ======== //

    LocalSealedBidBatchAuction.Decrypt[] internal decryptedBids;
    uint256 internal marginalPrice;

    modifier givenLotHasDecimals(uint8 baseTokenDecimals_, uint8 quoteTokenDecimals_) {
        // Set up tokens
        baseToken = new MockERC20("Base Token", "BASE", baseTokenDecimals_);
        quoteToken = new MockERC20("Quote Token", "QUOTE", quoteTokenDecimals_);

        quoteTokenDecimals = quoteTokenDecimals_;
        baseTokenDecimals = baseTokenDecimals_;

        // Update parameters
        _lotCapacity = _lotCapacity * 10 ** baseTokenDecimals_ / SCALE;

        auctionDataParams.minimumPrice = MINIMUM_PRICE * 10 ** quoteTokenDecimals_ / SCALE;

        auctionParams.capacity = _lotCapacity;
        auctionParams.implParams = abi.encode(auctionDataParams);

        routingParams.baseToken = baseToken;
        routingParams.quoteToken = quoteToken;

        // Update bid scale
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

        // Set up pre-funding
        baseToken.mint(auctionOwner, _lotCapacity);
        vm.prank(auctionOwner);
        baseToken.approve(address(auctionHouse), _lotCapacity);

        // Create a new auction
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    modifier givenLotHasBidsLessThanCapacity() {
        // Mint quote tokens to the bidders
        quoteToken.mint(bidderOne, bidOneAmount);

        // Authorise spending
        vm.prank(bidderOne);
        quoteToken.approve(address(auctionHouse), bidOneAmount);

        // Create bids
        // 4 < 10
        (, LocalSealedBidBatchAuction.Decrypt memory decryptedBidOne) =
            _createBid(bidderOne, bidOneAmount, bidOneAmountOut);
        decryptedBids.push(decryptedBidOne);

        // bidOne first (price = 1)
        marginalPrice = _getMarginalPriceScaled(bidOneAmount, bidOneAmountOut);
        _;
    }

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

        // bidOne first (price = 1), then bidTwo (price = 1)
        marginalPrice = _getMarginalPriceScaled(bidTwoAmount, bidTwoAmountOut);
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

        // bidOne first (price = 1), then bidThree (price = 1)
        marginalPrice = _getMarginalPriceScaled(bidThreeAmount, bidThreeAmountOut);
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
        marginalPrice = _getMarginalPriceScaled(bidFiveAmount, bidFiveAmountOut);
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
    // [X] when the caller is not authorized to settle
    //  [X] it reverts
    // [X] when the auction module reverts
    //  [X] it reverts
    // [X] given the auction house has insufficient balance of the quote token
    //  [X] it reverts
    // [X] given the auction house has insufficient balance of the base token
    //  [X] it reverts
    // [X] given that the capacity is not filled
    //  [X] it succeeds - transfers remaining base tokens back to the owner
    // [X] given the last bidder has a partial fill
    //  [X] it succeeds - last bidder receives the partial fill and is returned excess quote tokens
    // [X] given the auction bids have different prices
    //  [X] it succeeds
    // [X] given that the quote token decimals differ from the base token decimals
    //  [X] it succeeds
    // [X] it succeeds - auction owner receives quote tokens (minus fees), bidders receive base tokens and fees accrued

    function test_invalidLotId() external givenLotIdIsInvalid givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Attempt to settle the lot
        auctionHouse.settle(lotId);
    }

    function test_unauthorized() external {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Attempt to settle the lot
        vm.prank(bidderOne);
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
        assertEq(
            baseToken.balanceOf(auctionOwner), 0, "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
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

    function test_success_quoteTokenDecimalsLarger()
        external
        givenLotHasDecimals(17, 13)
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
        assertEq(
            baseToken.balanceOf(auctionOwner), 0, "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
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

    function test_success_quoteTokenDecimalsSmaller()
        external
        givenLotHasDecimals(13, 17)
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
        assertEq(
            baseToken.balanceOf(auctionOwner), 0, "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
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
        assertEq(
            baseToken.balanceOf(auctionOwner), 0, "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
        );

        // Check quote token balances
        uint256 bidOneAmountActual = 3e18; // 3
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

    function test_partialFill_quoteTokenDecimalsLarger()
        external
        givenLotHasDecimals(17, 13)
        givenLotHasStarted
        givenLotHasPartialFill
        givenLotHasConcluded
        givenLotHasDecrypted
    {
        // Attempt to settle the lot
        auctionHouse.settle(lotId);

        // Check base token balances
        uint256 bidOneAmountOutActual = 3 * 10 ** baseTokenDecimals;
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
        assertEq(
            baseToken.balanceOf(auctionOwner), 0, "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
        );

        // Check quote token balances
        uint256 bidOneAmountActual = 3 * 10 ** quoteTokenDecimals; // 3
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

    function test_partialFill_quoteTokenDecimalsSmaller()
        external
        givenLotHasDecimals(13, 17)
        givenLotHasStarted
        givenLotHasPartialFill
        givenLotHasConcluded
        givenLotHasDecrypted
    {
        // Attempt to settle the lot
        auctionHouse.settle(lotId);

        // Check base token balances
        uint256 bidOneAmountOutActual = 3 * 10 ** baseTokenDecimals;
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
        assertEq(
            baseToken.balanceOf(auctionOwner), 0, "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
        );

        // Check quote token balances
        uint256 bidOneAmountActual = 3 * 10 ** quoteTokenDecimals; // 3
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
        uint256 bidFourAmountOutActual = bidFourAmount * SCALE / marginalPrice;
        assertEq(
            baseToken.balanceOf(bidderOne),
            bidFourAmountOutActual,
            "bidderOne: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(bidderTwo),
            bidFiveAmountOut,
            "bidderTwo: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(auctionOwner),
            _lotCapacity - bidFourAmountOutActual - bidFiveAmountOut, // Returned remaining base tokens
            "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
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

    function test_marginalPrice_quoteTokenDecimalsLarger()
        external
        givenLotHasDecimals(17, 13)
        givenLotHasStarted
        givenLotHasSufficientBids_differentMarginalPrice
        givenLotHasConcluded
        givenLotHasDecrypted
    {
        // Attempt to settle the lot
        auctionHouse.settle(lotId);

        // Check base token balances
        uint256 bidFourAmountOutActual = _getAmountOut(bidFourAmount, marginalPrice);
        assertEq(
            baseToken.balanceOf(bidderOne),
            bidFourAmountOutActual,
            "bidderOne: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(bidderTwo),
            bidFiveAmountOut,
            "bidderTwo: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(auctionOwner),
            _lotCapacity - bidFourAmountOutActual - bidFiveAmountOut, // Returned remaining base tokens
            "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
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

    function test_marginalPrice_quoteTokenDecimalsSmaller()
        external
        givenLotHasDecimals(13, 17)
        givenLotHasStarted
        givenLotHasSufficientBids_differentMarginalPrice
        givenLotHasConcluded
        givenLotHasDecrypted
    {
        // Attempt to settle the lot
        auctionHouse.settle(lotId);

        // Check base token balances
        uint256 bidFourAmountOutActual = _getAmountOut(bidFourAmount, marginalPrice);
        assertEq(
            baseToken.balanceOf(bidderOne),
            bidFourAmountOutActual,
            "bidderOne: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(bidderTwo),
            bidFiveAmountOut,
            "bidderTwo: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(auctionOwner),
            _lotCapacity - bidFourAmountOutActual - bidFiveAmountOut, // Returned remaining base tokens
            "auction owner: incorrect balance of base token"
        );
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
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

    function test_lessThanCapacity()
        external
        givenLotHasStarted
        givenLotHasBidsLessThanCapacity
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
        assertEq(baseToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of base token");
        assertEq(
            baseToken.balanceOf(auctionOwner),
            _lotCapacity - bidOneAmountOut,
            "auction owner: incorrect balance of base token"
        ); // Returned remaining base tokens
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
        );

        // Check quote token balances
        assertEq(quoteToken.balanceOf(bidderOne), 0, "bidderOne: incorrect balance of quote token");
        assertEq(quoteToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of quote token");

        // Calculate fees on quote tokens
        uint256 protocolFeeAmount = (bidOneAmount + 0) * protocolFee / 1e5;
        uint256 referrerFeeAmount = (bidOneAmount + 0) * referrerFee / 1e5;
        uint256 totalFeeAmount = protocolFeeAmount + referrerFeeAmount;

        // Auction owner should have received quote tokens minus fees
        assertEq(
            quoteToken.balanceOf(auctionOwner),
            bidOneAmount + 0 - totalFeeAmount,
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

    function test_lessThanCapacity_quoteTokenDecimalsLarger()
        external
        givenLotHasDecimals(17, 13)
        givenLotHasStarted
        givenLotHasBidsLessThanCapacity
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
        assertEq(baseToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of base token");
        assertEq(
            baseToken.balanceOf(auctionOwner),
            _lotCapacity - bidOneAmountOut,
            "auction owner: incorrect balance of base token"
        ); // Returned remaining base tokens
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
        );

        // Check quote token balances
        assertEq(quoteToken.balanceOf(bidderOne), 0, "bidderOne: incorrect balance of quote token");
        assertEq(quoteToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of quote token");

        // Calculate fees on quote tokens
        uint256 protocolFeeAmount = (bidOneAmount + 0) * protocolFee / 1e5;
        uint256 referrerFeeAmount = (bidOneAmount + 0) * referrerFee / 1e5;
        uint256 totalFeeAmount = protocolFeeAmount + referrerFeeAmount;

        // Auction owner should have received quote tokens minus fees
        assertEq(
            quoteToken.balanceOf(auctionOwner),
            bidOneAmount + 0 - totalFeeAmount,
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

    function test_lessThanCapacity_quoteTokenDecimalsSmaller()
        external
        givenLotHasDecimals(13, 17)
        givenLotHasStarted
        givenLotHasBidsLessThanCapacity
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
        assertEq(baseToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of base token");
        assertEq(
            baseToken.balanceOf(auctionOwner),
            _lotCapacity - bidOneAmountOut,
            "auction owner: incorrect balance of base token"
        ); // Returned remaining base tokens
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            0,
            "auctionHouse: incorrect balance of base token"
        );

        // Check quote token balances
        assertEq(quoteToken.balanceOf(bidderOne), 0, "bidderOne: incorrect balance of quote token");
        assertEq(quoteToken.balanceOf(bidderTwo), 0, "bidderTwo: incorrect balance of quote token");

        // Calculate fees on quote tokens
        uint256 protocolFeeAmount = (bidOneAmount + 0) * protocolFee / 1e5;
        uint256 referrerFeeAmount = (bidOneAmount + 0) * referrerFee / 1e5;
        uint256 totalFeeAmount = protocolFeeAmount + referrerFeeAmount;

        // Auction owner should have received quote tokens minus fees
        assertEq(
            quoteToken.balanceOf(auctionOwner),
            bidOneAmount + 0 - totalFeeAmount,
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
