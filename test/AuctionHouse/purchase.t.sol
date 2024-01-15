// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {IPermit2} from "src/lib/permit2/interfaces/IPermit2.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/Derivative/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {MockHook} from "test/modules/Auction/MockHook.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

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
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;
    Router.PurchaseParams internal purchaseParams;

    address internal immutable protocol = address(0x2);
    address internal immutable alice = address(0x3);
    address internal immutable referrer = address(0x4);
    address internal immutable auctionOwner = address(0x5);

    uint256 internal lotId;

    uint256 internal constant AMOUNT_IN = 1e18;
    uint256 internal AMOUNT_OUT;

    uint256 internal constant APPROVAL_NONCE = 222;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(protocol, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockCondenserModule = new MockCondenserModule(address(auctionHouse));
        mockAllowlist = new MockAllowlist();
        mockHook = new MockHook();

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: 10e18,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("ATOM"),
            baseToken: baseToken,
            quoteToken: quoteToken,
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

        // Set the default payout multiplier to 1
        mockAuctionModule.setPayoutMultiplier(lotId, 1);

        // 1:1 exchange rate
        AMOUNT_OUT = AMOUNT_IN;

        purchaseParams = Router.PurchaseParams({
            recipient: alice,
            referrer: referrer,
            approvalDeadline: uint48(block.timestamp),
            lotId: lotId,
            amount: AMOUNT_IN,
            minAmountOut: AMOUNT_OUT,
            approvalNonce: APPROVAL_NONCE,
            auctionData: bytes(""),
            approvalSignature: bytes("")
        });
    }

    modifier whenDerivativeModuleIsInstalled() {
        auctionHouse.installModule(mockDerivativeModule);
        _;
    }

    modifier whenDerivativeTypeIsSet() {
        routingParams.derivativeType = toKeycode("DERV");
        _;
    }

    modifier whenCondenserModuleIsInstalled() {
        auctionHouse.installModule(mockCondenserModule);
        _;
    }

    modifier whenCondenserIsMapped() {
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
        _;
    }

    modifier whenAccountHasQuoteTokenBalance(uint256 amount_) {
        quoteToken.mint(alice, amount_);
        _;
    }

    modifier whenAccountHasBaseTokenBalance(uint256 amount_) {
        baseToken.mint(auctionOwner, amount_);
        _;
    }

    modifier whenAuctionIsCancelled() {
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);
        _;
    }

    modifier whenPermit2IsApproved() {
        // TODO
        _;
    }

    modifier whenPermit2ApprovalIsValid() {
        // TODO
        _;
    }

    // parameter checks
    // [ ] when the lot id is invalid
    //  [ ] it reverts
    // [ ] given the auction is not atomic
    //  [ ] it reverts
    // [ ] given the auction is not active
    //  [ ] it reverts
    // [ ] when the auction module reverts
    //  [ ] it reverts
    // [ ] when the calculated payout amount is less than the minimum
    //  [ ] it reverts
    //
    // allowlist
    // [ ] when the caller is not on the allowlist
    //  [ ] it reverts
    // [ ] when the caller is on the allowlist
    //  [ ] it succeeds
    //
    // exchange of quote and base tokens
    // [ ] given the auction has hooks defined
    //  [ ] when the mid hook reverts
    //   [ ] it reverts
    //  [ ] when the mid hook does not transfer enough base tokens to the auction house
    //   [ ] it reverts
    //  [ ] when the mid hook transfers enough base tokens to the auction house
    //   [ ] it succeeds - quote tokens (minus fees) transferred to the auction owner
    // [ ] given the auction does not have hooks defined
    //   [ ] given that approval has not been given to the auction house to transfer base tokens
    //    [ ] it reverts
    //   [ ] given the received amount is less than the transferred amount
    //    [ ] it reverts
    //   [ ] given the received amount is the same as the transferred amount
    //    [ ] quote tokens (minus fees) are transferred to the auction owner
    //
    // transfers base token from auction house to recipient
    // [ ] given the base token is a derivative
    //  [ ] given a condenser is set
    //   [ ] it uses the condenser to determine derivative parameters
    //  [ ] given a condenser is not set
    //   [ ] it uses the routing derivative parameters
    //  [ ] it mints derivative tokens to the recipient using the derivative module
    // [ ] given the base token is not a derivative
    //  [ ] it transfers the base token to the recipient
    //
    // records fees
    // [ ] given that a protocol fee is defined
    //  [ ] it records the protocol fee
    // [ ] given that a referrer fee is defined
    //  [ ] it records the referrer fee

    function testReverts_whenLotIdIsInvalid() external {
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

    function testReverts_whenNotAtomicAuction()
        external
        whenBatchAuctionIsCreated
        whenAccountHasQuoteTokenBalance(AMOUNT_IN)
        whenAccountHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Update purchase params
        purchaseParams.lotId = lotId;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
        vm.expectRevert(err);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function testReverts_whenAuctionNotActive()
        external
        whenAuctionIsCancelled
        whenAccountHasQuoteTokenBalance(AMOUNT_IN)
        whenAccountHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function testReverts_whenAuctionModuleReverts()
        external
        whenAccountHasQuoteTokenBalance(AMOUNT_IN)
        whenAccountHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Set the auction module to revert
        mockAuctionModule.setPurchaseReverts(true);

        // Expect revert
        vm.expectRevert("error");

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function testReverts_whenPayoutAmountLessThanMinimum()
        external
        whenAccountHasQuoteTokenBalance(AMOUNT_IN)
        whenAccountHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Set the payout multiplier so that the payout is less than the minimum
        mockAuctionModule.setPayoutMultiplier(lotId, 0);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function testReverts_whenCallerHasInsufficientBalanceOfQuoteToken()
        external
        whenAccountHasBaseTokenBalance(AMOUNT_OUT)
    {
        // Expect revert
        vm.expectRevert();

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }

    function testReverts_whenOwnerHasInsufficientBalanceOfBaseToken()
        external
        whenAccountHasQuoteTokenBalance(AMOUNT_IN)
    {
        // Expect revert
        vm.expectRevert();

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
    }
}
