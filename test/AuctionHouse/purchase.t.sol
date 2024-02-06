// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IPermit2} from "src/lib/permit2/interfaces/IPermit2.sol";

// Mocks
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/Derivative/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {MockHook} from "test/modules/Auction/MockHook.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {AuctionHouse, Router, FeeManager} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {IHooks, IAllowlist, Auctioneer} from "src/bases/Auctioneer.sol";

// Modules
import {
    Keycode,
    toKeycode,
    Veecode,
    wrapVeecode,
    fromVeecode,
    WithModules,
    Module
} from "src/modules/Modules.sol";

contract PurchaseTest is Test, Permit2User {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAtomicAuctionModule internal mockAuctionModule;
    MockDerivativeModule internal mockDerivativeModule;
    MockCondenserModule internal mockCondenserModule;
    MockAllowlist internal mockAllowlist;
    MockHook internal mockHook;

    AuctionHouse internal auctionHouse;

    address internal immutable protocol = address(0x2);
    address internal immutable referrer = address(0x4);
    address internal immutable auctionOwner = address(0x5);
    address internal immutable recipient = address(0x6);

    uint256 internal aliceKey;
    address internal alice;

    uint96 internal lotId;

    uint256 internal constant LOT_CAPACITY = 10e18;

    uint256 internal constant AMOUNT_IN = 1e18;
    uint256 internal AMOUNT_OUT;

    uint48 internal constant DERIVATIVE_EXPIRY = 1 days;

    uint48 internal referrerFee;
    uint48 internal protocolFee;

    uint256 internal amountInLessFee;
    uint256 internal amountInReferrerFee;
    uint256 internal amountInProtocolFee;

    // Function parameters (can be modified)
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;
    Router.PurchaseParams internal purchaseParams;
    uint256 internal approvalNonce;
    bytes internal approvalSignature;
    uint48 internal approvalDeadline;
    uint256 internal derivativeTokenId;
    bytes internal allowlistProof;

    function setUp() external {
        aliceKey = _getRandomUint256();
        alice = vm.addr(aliceKey);

        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(protocol, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockCondenserModule = new MockCondenserModule(address(auctionHouse));
        mockAllowlist = new MockAllowlist();
        mockHook = new MockHook(address(quoteToken), address(baseToken));

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("ATOM"),
            baseToken: baseToken,
            quoteToken: quoteToken,
            curator: address(0),
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            payoutData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode("")
        });

        // Install the auction module
        auctionHouse.installModule(mockAuctionModule);

        // Create an auction
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);

        // Fees
        referrerFee = 1000;
        protocolFee = 2000;
        auctionHouse.setFee(toKeycode("ATOM"), FeeManager.FeeType.Protocol, protocolFee);
        auctionHouse.setFee(toKeycode("ATOM"), FeeManager.FeeType.Referrer, referrerFee);

        amountInReferrerFee = (AMOUNT_IN * referrerFee) / 1e5;
        amountInProtocolFee = (AMOUNT_IN * protocolFee) / 1e5;
        amountInLessFee = AMOUNT_IN - amountInReferrerFee - amountInProtocolFee;

        // 1:1 exchange rate
        AMOUNT_OUT = amountInLessFee;

        // Purchase parameters
        purchaseParams = Router.PurchaseParams({
            recipient: recipient,
            referrer: referrer,
            lotId: lotId,
            amount: AMOUNT_IN,
            minAmountOut: AMOUNT_OUT,
            auctionData: bytes(""),
            allowlistProof: allowlistProof,
            permit2Data: bytes("")
        });
    }

    modifier givenDerivativeModuleIsInstalled() {
        auctionHouse.installModule(mockDerivativeModule);
        _;
    }

    modifier givenDerivativeHasCondenser() {
        // Install the condenser module
        auctionHouse.installModule(mockCondenserModule);

        // Set the condenser
        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockCondenserModule.VEECODE()
        );
        _;
    }

    modifier whenBatchAuctionIsCreated() {
        MockBatchAuctionModule mockBatchAuctionModule =
            new MockBatchAuctionModule(address(auctionHouse));

        // Install the batch auction module
        auctionHouse.installModule(mockBatchAuctionModule);

        // Modify the routing params to create a batch auction
        routingParams.auctionType = toKeycode("BATCH");

        // Create the batch auction
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);

        // Update purchase parameters
        purchaseParams.lotId = lotId;
        _;
    }

    modifier givenUserHasQuoteTokenBalance(uint256 amount_) {
        quoteToken.mint(alice, amount_);
        _;
    }

    modifier givenOwnerHasBaseTokenBalance(uint256 amount_) {
        baseToken.mint(auctionOwner, amount_);
        _;
    }

    modifier givenHookHasBaseTokenBalance(uint256 amount_) {
        baseToken.mint(address(mockHook), amount_);
        _;
    }

    modifier givenAuctionIsCancelled() {
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);
        _;
    }

    modifier givenQuoteTokenSpendingIsApproved() {
        vm.prank(alice);
        quoteToken.approve(address(auctionHouse), AMOUNT_IN);
        _;
    }

    modifier givenQuoteTokenPermit2IsApproved() {
        vm.prank(alice);
        quoteToken.approve(address(_PERMIT2_ADDRESS), type(uint256).max);
        _;
    }

    modifier givenBaseTokenSpendingIsApproved() {
        vm.prank(auctionOwner);
        baseToken.approve(address(auctionHouse), AMOUNT_OUT);
        _;
    }

    modifier givenAuctionHasHooks() {
        routingParams.hooks = IHooks(address(mockHook));

        // Create a new auction with the hooks
        lotId = auctionHouse.auction(routingParams, auctionParams);

        // Update the purchase params
        purchaseParams.lotId = lotId;
        _;
    }

    // parameter checks
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the auction is not atomic
    //  [X] it reverts
    // [X] given the auction is not active
    //  [X] it reverts
    // [X] when the auction module reverts
    //  [X] it reverts

    function test_whenLotIdIsInvalid_reverts() external {
        // Update the lot id to an invalid value
        purchaseParams.lotId = 1;

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, purchaseParams.lotId);
        vm.expectRevert(err);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function test_whenNotAtomicAuction_reverts()
        external
        whenBatchAuctionIsCreated
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
        vm.expectRevert(err);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function test_whenAuctionNotActive_reverts()
        external
        givenAuctionIsCancelled
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function test_whenAuctionModuleReverts_reverts()
        external
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Set the auction module to revert
        mockAuctionModule.setPurchaseReverts(true);

        // Expect revert
        vm.expectRevert("error");

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function test_whenPayoutAmountLessThanMinimum_reverts()
        external
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Set the payout multiplier so that the payout is less than the minimum
        mockAuctionModule.setPayoutMultiplier(lotId, 90_000);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    // allowlist
    // [X] given an allowlist is set
    //  [X] when the caller is not on the allowlist
    //   [X] it reverts
    //  [X] when the caller is on the allowlist
    //   [X] it succeeds

    modifier givenAuctionHasAllowlist() {
        // Register a new auction with an allowlist
        routingParams.allowlist = mockAllowlist;

        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);

        // Update the purchase params
        purchaseParams.lotId = lotId;
        _;
    }

    modifier givenCallerIsOnAllowlist() {
        // Assumes the allowlist is set
        require(address(routingParams.allowlist) != address(0), "allowlist not set");

        // Set the allowlist proof
        allowlistProof = abi.encode("i am allowed");

        // Set the caller to be on the allowlist
        mockAllowlist.setAllowedWithProof(alice, allowlistProof, true);

        // Update the purchase params
        purchaseParams.allowlistProof = allowlistProof;
        _;
    }

    function test_givenCallerNotOnAllowlist() external givenAuctionHasAllowlist {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidBidder.selector, alice);
        vm.expectRevert(err);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function test_givenCallerOnAllowlist()
        external
        givenAuctionHasAllowlist
        givenCallerIsOnAllowlist
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
        givenQuoteTokenSpendingIsApproved
        givenBaseTokenSpendingIsApproved
    {
        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);

        // Caller has no quote tokens
        assertEq(quoteToken.balanceOf(alice), 0);

        // Recipient has base tokens
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(recipient), amountInLessFee);
    }

    // transfer quote token to auction house
    // [X] when the permit2 signature is provided
    //  [X] it succeeds using Permit2
    // [X] when the permit2 signature is not provided
    //  [X] it succeeds using ERC20 transfer

    modifier whenPermit2DataIsProvided() {
        approvalNonce = _getRandomUint256();
        approvalDeadline = uint48(block.timestamp) + 1 days;
        approvalSignature = _signPermit(
            address(quoteToken),
            AMOUNT_IN,
            approvalNonce,
            approvalDeadline,
            address(auctionHouse),
            aliceKey
        );

        // Update parameters
        purchaseParams.permit2Data = abi.encode(
            Router.Permit2Approval({
                deadline: approvalDeadline,
                nonce: approvalNonce,
                signature: approvalSignature
            })
        );
        _;
    }

    function test_whenPermit2Signature()
        external
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
        givenBaseTokenSpendingIsApproved
        givenQuoteTokenPermit2IsApproved
        whenPermit2DataIsProvided
    {
        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);

        // Check balances
        assertEq(quoteToken.balanceOf(alice), 0);
        assertEq(quoteToken.balanceOf(recipient), 0);
        assertEq(quoteToken.balanceOf(address(mockHook)), 0);
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)), amountInProtocolFee + amountInReferrerFee
        );
        assertEq(quoteToken.balanceOf(auctionOwner), amountInLessFee);

        // Ignore the rest
    }

    function test_whenNoPermit2Signature()
        external
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
        givenQuoteTokenSpendingIsApproved
        givenBaseTokenSpendingIsApproved
    {
        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);

        // Check balances
        assertEq(quoteToken.balanceOf(alice), 0);
        assertEq(quoteToken.balanceOf(recipient), 0);
        assertEq(quoteToken.balanceOf(address(mockHook)), 0);
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)), amountInProtocolFee + amountInReferrerFee
        );
        assertEq(quoteToken.balanceOf(auctionOwner), amountInLessFee);

        // Ignore the rest
    }

    // [X] given the auction has hooks defined
    //  [X] it succeeds - quote token transferred to hook, payout token (minus fees) transferred to recipient
    // [X] given the auction does not have hooks defined
    //  [X] it succeeds - quote token transferred to auction owner, payout token (minus fees) transferred to recipient

    function test_hooks()
        public
        givenAuctionHasHooks
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenHookHasBaseTokenBalance(AMOUNT_OUT)
        givenQuoteTokenSpendingIsApproved
        givenBaseTokenSpendingIsApproved
    {
        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);

        // Check balances
        assertEq(quoteToken.balanceOf(alice), 0);
        assertEq(quoteToken.balanceOf(recipient), 0);
        assertEq(quoteToken.balanceOf(address(mockHook)), amountInLessFee);
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)), amountInProtocolFee + amountInReferrerFee
        );
        assertEq(quoteToken.balanceOf(auctionOwner), 0);

        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(recipient), AMOUNT_OUT);
        assertEq(baseToken.balanceOf(address(mockHook)), 0);
        assertEq(baseToken.balanceOf(address(auctionHouse)), 0);
        assertEq(baseToken.balanceOf(auctionOwner), 0);

        // Check accrued fees
        assertEq(auctionHouse.rewards(alice, quoteToken), 0);
        assertEq(auctionHouse.rewards(recipient, quoteToken), 0);
        assertEq(auctionHouse.rewards(referrer, quoteToken), amountInReferrerFee);
        assertEq(auctionHouse.rewards(protocol, quoteToken), amountInProtocolFee);
        assertEq(auctionHouse.rewards(address(mockHook), quoteToken), 0);
        assertEq(auctionHouse.rewards(address(auctionHouse), quoteToken), 0);
        assertEq(auctionHouse.rewards(auctionOwner, quoteToken), 0);

        assertEq(auctionHouse.rewards(alice, baseToken), 0);
        assertEq(auctionHouse.rewards(recipient, baseToken), 0);
        assertEq(auctionHouse.rewards(referrer, baseToken), 0);
        assertEq(auctionHouse.rewards(protocol, baseToken), 0);
        assertEq(auctionHouse.rewards(address(mockHook), baseToken), 0);
        assertEq(auctionHouse.rewards(address(auctionHouse), baseToken), 0);
        assertEq(auctionHouse.rewards(auctionOwner, baseToken), 0);
    }

    function test_noHooks()
        public
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
        givenQuoteTokenSpendingIsApproved
        givenBaseTokenSpendingIsApproved
    {
        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);

        // Check balances
        assertEq(quoteToken.balanceOf(alice), 0);
        assertEq(quoteToken.balanceOf(recipient), 0);
        assertEq(quoteToken.balanceOf(address(mockHook)), 0);
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)), amountInProtocolFee + amountInReferrerFee
        );
        assertEq(quoteToken.balanceOf(auctionOwner), amountInLessFee);

        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(recipient), AMOUNT_OUT);
        assertEq(baseToken.balanceOf(address(mockHook)), 0);
        assertEq(baseToken.balanceOf(address(auctionHouse)), 0);
        assertEq(baseToken.balanceOf(auctionOwner), 0);

        // Check accrued fees
        assertEq(auctionHouse.rewards(alice, quoteToken), 0);
        assertEq(auctionHouse.rewards(recipient, quoteToken), 0);
        assertEq(auctionHouse.rewards(referrer, quoteToken), amountInReferrerFee);
        assertEq(auctionHouse.rewards(protocol, quoteToken), amountInProtocolFee);
        assertEq(auctionHouse.rewards(address(mockHook), quoteToken), 0);
        assertEq(auctionHouse.rewards(address(auctionHouse), quoteToken), 0);
        assertEq(auctionHouse.rewards(auctionOwner, quoteToken), 0);

        assertEq(auctionHouse.rewards(alice, baseToken), 0);
        assertEq(auctionHouse.rewards(recipient, baseToken), 0);
        assertEq(auctionHouse.rewards(referrer, baseToken), 0);
        assertEq(auctionHouse.rewards(protocol, baseToken), 0);
        assertEq(auctionHouse.rewards(address(mockHook), baseToken), 0);
        assertEq(auctionHouse.rewards(address(auctionHouse), baseToken), 0);
        assertEq(auctionHouse.rewards(auctionOwner, baseToken), 0);
    }

    // ======== Derivative flow ======== //

    modifier givenAuctionHasDerivative() {
        // Install the derivative module
        auctionHouse.installModule(mockDerivativeModule);

        // Deploy a new derivative token
        MockDerivativeModule.DerivativeParams memory deployParams =
            MockDerivativeModule.DerivativeParams({expiry: DERIVATIVE_EXPIRY, multiplier: 0});
        (uint256 tokenId,) =
            mockDerivativeModule.deploy(address(baseToken), abi.encode(deployParams), false);

        // Set up a new auction with a derivative
        derivativeTokenId = tokenId;
        routingParams.derivativeType = toKeycode("DERV");
        routingParams.derivativeParams = abi.encode(deployParams);

        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);

        // Set purchase parameters
        purchaseParams.lotId = lotId;
        _;
    }

    // [X] given the auction has a derivative defined
    //  [X] it succeeds - derivative is minted

    function test_derivative()
        public
        givenAuctionHasDerivative
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(AMOUNT_OUT)
        givenQuoteTokenSpendingIsApproved
        givenBaseTokenSpendingIsApproved
    {
        // Call
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);

        // Check balances of the quote token
        assertEq(quoteToken.balanceOf(alice), 0);
        assertEq(quoteToken.balanceOf(recipient), 0);
        assertEq(quoteToken.balanceOf(address(mockHook)), 0);
        assertEq(
            quoteToken.balanceOf(address(auctionHouse)), amountInProtocolFee + amountInReferrerFee
        );
        assertEq(quoteToken.balanceOf(auctionOwner), amountInLessFee);
        assertEq(quoteToken.balanceOf(address(mockDerivativeModule)), 0);

        // Check balances of the base token
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(recipient), 0);
        assertEq(baseToken.balanceOf(address(mockHook)), 0);
        assertEq(baseToken.balanceOf(address(auctionHouse)), 0);
        assertEq(baseToken.balanceOf(auctionOwner), 0);
        assertEq(baseToken.balanceOf(address(mockDerivativeModule)), AMOUNT_OUT);

        // Check balances of the derivative token
        assertEq(mockDerivativeModule.derivativeToken().balanceOf(alice, derivativeTokenId), 0);
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(recipient, derivativeTokenId),
            AMOUNT_OUT
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(address(mockHook), derivativeTokenId),
            0
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(
                address(auctionHouse), derivativeTokenId
            ),
            0
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(auctionOwner, derivativeTokenId), 0
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(
                address(mockDerivativeModule), derivativeTokenId
            ),
            0
        );
    }

    // [ ] given there is no protocol fee set for the auction type
    //  [ ] no protocol fee is accrued
    // [ ] the protocol fee is accrued

    // [ ] given there is no referrer fee set for the auction type
    //  [ ] no referrer fee is accrued
    // [ ] the referrer fee is accrued

    // [ ] given there is no curator set
    //  [ ] no payout token is transferred to the curator
    // [ ] given there is a curator set
    //  [ ] given the curator has not approved curation
    //   [ ] no payout token is transferred to the curator
    //  [ ] given the payout token is a derivative
    //   [ ] derivative is minted and transferred to the curator
    //  [ ] payout token is transferred to the curator

    // ======== Prefunding flow ======== //

    // [X] given the auction is prefunded
    //  [X] it succeeds - base token is not transferred from auction owner again

    modifier givenAuctionIsPrefunded() {
        // Set the auction to be prefunded
        mockAuctionModule.setRequiredPrefunding(true);

        // Mint base tokens to the owner
        baseToken.mint(auctionOwner, LOT_CAPACITY);

        // Approve the auction house to transfer the base tokens
        vm.prank(auctionOwner);
        baseToken.approve(address(auctionHouse), LOT_CAPACITY);

        // Create a new auction
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);

        // Update purchase parameters
        purchaseParams.lotId = lotId;
        _;
    }

    function test_prefunded()
        external
        givenAuctionIsPrefunded
        givenUserHasQuoteTokenBalance(AMOUNT_IN)
        givenQuoteTokenSpendingIsApproved
    {
        // Auction house has base tokens
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            LOT_CAPACITY,
            "pre-purchase: balance mismatch on auction house"
        );

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);

        // Check balances of the base token
        assertEq(baseToken.balanceOf(alice), 0, "balance mismatch on alice");
        assertEq(baseToken.balanceOf(recipient), AMOUNT_OUT, "balance mismatch on recipient");
        assertEq(baseToken.balanceOf(address(mockHook)), 0, "balance mismatch on hook");
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            LOT_CAPACITY - AMOUNT_OUT,
            "balance mismatch on auction house"
        );
        assertEq(baseToken.balanceOf(auctionOwner), 0, "balance mismatch on auction owner");
    }
}
