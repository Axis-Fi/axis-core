/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Transfer} from "src/lib/Transfer.sol";

import {MockHook} from "test/modules/Auction/MockHook.sol";
import {MockAuctionHouse} from "test/AuctionHouse/MockAuctionHouse.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockWrappedDerivative} from "test/lib/mocks/MockWrappedDerivative.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AuctionHouse} from "src/AuctionHouse.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {Veecode, toVeecode, wrapVeecode, toKeycode} from "src/modules/Modules.sol";

contract SendPayoutTest is Test, Permit2User {
    MockAuctionHouse internal auctionHouse;
    MockAtomicAuctionModule internal mockAuctionModule;
    MockDerivativeModule internal mockDerivativeModule;
    MockCondenserModule internal mockCondenserModule;
    MockWrappedDerivative internal derivativeWrappedImplementation;

    address internal constant PROTOCOL = address(0x1);

    address internal USER = address(0x2);
    address internal OWNER = address(0x3);
    address internal RECIPIENT = address(0x4);

    uint48 internal constant DERIVATIVE_EXPIRY = 1 days;

    // Function parameters
    uint96 internal lotId = 1;
    uint256 internal payoutAmount = 10e18;
    MockFeeOnTransferERC20 internal quoteToken;
    MockFeeOnTransferERC20 internal payoutToken;
    MockHook internal hook;
    Veecode internal derivativeReference;
    uint256 internal derivativeTokenId;
    bytes internal derivativeParams;
    bool internal wrapDerivative;
    ERC20 internal wrappedDerivative;
    uint256 internal auctionOutputMultiplier;
    bytes internal auctionOutput;

    Auctioneer.Routing internal routingParams;

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        auctionHouse = new MockAuctionHouse(PROTOCOL, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockCondenserModule = new MockCondenserModule(address(auctionHouse));
        auctionHouse.installModule(mockAuctionModule);

        derivativeWrappedImplementation = new MockWrappedDerivative("name", "symbol", 18);
        mockDerivativeModule.setWrappedImplementation(derivativeWrappedImplementation);

        quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);
        quoteToken.setTransferFee(0);

        payoutToken = new MockFeeOnTransferERC20("Payout Token", "PAYOUT", 18);
        payoutToken.setTransferFee(0);

        derivativeReference = toVeecode(bytes7(""));
        derivativeParams = bytes("");
        wrapDerivative = false;
        auctionOutputMultiplier = 2;
        auctionOutput =
            abi.encode(MockAtomicAuctionModule.Output({multiplier: auctionOutputMultiplier})); // Does nothing unless the condenser is set

        routingParams = Auctioneer.Routing({
            auctionReference: mockAuctionModule.VEECODE(),
            owner: OWNER,
            baseToken: payoutToken,
            quoteToken: quoteToken,
            hooks: hook,
            allowlist: IAllowlist(address(0)),
            derivativeReference: derivativeReference,
            derivativeParams: derivativeParams,
            wrapDerivative: wrapDerivative,
            prefunding: 0
        });
    }

    modifier givenTokenTakesFeeOnTransfer() {
        payoutToken.setTransferFee(1000);
        _;
    }

    modifier givenAuctionHouseHasBalance(uint256 amount_) {
        payoutToken.mint(address(auctionHouse), amount_);
        _;
    }

    // ========== Hooks flow ========== //

    // [ ] given the auction has hooks defined
    //  [X] when the token is unsupported
    //   [X] it reverts
    //  [X] when the post hook reverts
    //   [X] it reverts
    //  [ ] when the post hook invariant is broken
    //   [ ] it reverts
    //  [X] it succeeds - transfers the payout from the auctionHouse to the recipient

    modifier givenAuctionHasHook() {
        hook = new MockHook(address(0), address(payoutToken));
        routingParams.hooks = hook;

        // Set the addresses to track
        address[] memory addresses = new address[](6);
        addresses[0] = USER;
        addresses[1] = OWNER;
        addresses[2] = address(auctionHouse);
        addresses[3] = address(hook);
        addresses[4] = RECIPIENT;
        addresses[5] = address(mockDerivativeModule);

        hook.setBalanceAddresses(addresses);
        _;
    }

    modifier givenPostHookReverts() {
        hook.setPostHookReverts(true);
        _;
    }

    function test_hooks_whenPostHookReverts_reverts()
        public
        givenAuctionHasHook
        givenPostHookReverts
        givenAuctionHouseHasBalance(payoutAmount)
    {
        // Expect revert
        vm.expectRevert("revert");

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_hooks_feeOnTransfer_reverts()
        public
        givenAuctionHasHook
        givenAuctionHouseHasBalance(payoutAmount)
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_hooks_insufficientBalance_reverts() public givenAuctionHasHook {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FAILED"));

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_hooks() public givenAuctionHasHook givenAuctionHouseHasBalance(payoutAmount) {
        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);

        // Check balances
        assertEq(payoutToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(payoutToken.balanceOf(OWNER), 0, "owner balance mismatch");
        assertEq(payoutToken.balanceOf(address(auctionHouse)), 0, "auctionHouse balance mismatch");
        assertEq(payoutToken.balanceOf(address(hook)), 0, "hook balance mismatch");
        assertEq(payoutToken.balanceOf(RECIPIENT), payoutAmount, "recipient balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            0,
            "derivative module balance mismatch"
        );

        // Check the hook was called at the right time
        assertEq(hook.preHookCalled(), false, "pre hook mismatch");
        assertEq(hook.midHookCalled(), false, "mid hook mismatch");
        assertEq(hook.postHookCalled(), true, "post hook mismatch");
        assertEq(hook.postHookBalances(payoutToken, USER), 0, "post hook user balance mismatch");
        assertEq(hook.postHookBalances(payoutToken, OWNER), 0, "post hook owner balance mismatch");
        assertEq(
            hook.postHookBalances(payoutToken, address(auctionHouse)),
            0,
            "post hook auctionHouse balance mismatch"
        );
        assertEq(
            hook.postHookBalances(payoutToken, address(hook)), 0, "post hook hook balance mismatch"
        );
        assertEq(
            hook.postHookBalances(payoutToken, RECIPIENT),
            payoutAmount,
            "post hook recipient balance mismatch"
        );
        assertEq(
            hook.postHookBalances(payoutToken, address(mockDerivativeModule)),
            0,
            "post hook derivative module balance mismatch"
        );
    }

    // ========== Non-hooks flow ========== //

    // [X] given the auction does not have hooks defined
    //  [X] given transferring the payout token would result in a lesser amount being received
    //   [X] it reverts
    //  [X] it succeeds - transfers the payout from the auctionHouse to the recipient

    function test_noHooks_feeOnTransfer_reverts()
        public
        givenAuctionHouseHasBalance(payoutAmount)
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_noHooks_insufficientBalance_reverts() public {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FAILED"));

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_noHooks() public givenAuctionHouseHasBalance(payoutAmount) {
        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);

        // Check balances
        assertEq(payoutToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(payoutToken.balanceOf(OWNER), 0, "owner balance mismatch");
        assertEq(payoutToken.balanceOf(address(auctionHouse)), 0, "auctionHouse balance mismatch");
        assertEq(payoutToken.balanceOf(address(hook)), 0, "hook balance mismatch");
        assertEq(payoutToken.balanceOf(RECIPIENT), payoutAmount, "recipient balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            0,
            "derivative module balance mismatch"
        );
    }

    // ========== Derivative flow ========== //

    // [X] given the base token is a derivative
    //  [X] given a condenser is set
    //   [X] given the derivative parameters are invalid
    //     [X] it reverts
    //   [X] it uses the condenser to determine derivative parameters
    //  [X] given a condenser is not set
    //   [X] given the derivative is wrapped
    //    [X] given the derivative parameters are invalid
    //     [X] it reverts
    //    [X] it mints wrapped derivative tokens to the recipient using the derivative module
    //   [X] given the derivative is not wrapped
    //    [X] given the derivative parameters are invalid
    //     [X] it reverts
    //    [X] it mints derivative tokens to the recipient using the derivative module

    modifier givenAuctionHasDerivative() {
        // Install the derivative module
        auctionHouse.installModule(mockDerivativeModule);

        // Deploy a new derivative token
        MockDerivativeModule.DerivativeParams memory deployParams =
            MockDerivativeModule.DerivativeParams({expiry: DERIVATIVE_EXPIRY, multiplier: 0});
        (uint256 tokenId,) =
            mockDerivativeModule.deploy(address(payoutToken), abi.encode(deployParams), false);

        // Update parameters
        derivativeReference = mockDerivativeModule.VEECODE();
        derivativeTokenId = tokenId;
        derivativeParams = abi.encode(deployParams);
        routingParams.derivativeReference = derivativeReference;
        routingParams.derivativeParams = derivativeParams;
        _;
    }

    modifier givenDerivativeIsWrapped() {
        // Deploy a new wrapped derivative token
        MockDerivativeModule.DerivativeParams memory deployParams =
            MockDerivativeModule.DerivativeParams({expiry: DERIVATIVE_EXPIRY + 1, multiplier: 0}); // Different expiry which leads to a different token id
        (uint256 tokenId_, address wrappedToken_) =
            mockDerivativeModule.deploy(address(payoutToken), abi.encode(deployParams), true);

        // Update parameters
        wrappedDerivative = ERC20(wrappedToken_);
        derivativeTokenId = tokenId_;
        derivativeParams = abi.encode(deployParams);
        routingParams.derivativeParams = derivativeParams;

        wrapDerivative = true;
        routingParams.wrapDerivative = wrapDerivative;
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

    modifier givenDerivativeParamsAreInvalid() {
        derivativeParams = abi.encode("one", "two", uint256(2));
        routingParams.derivativeParams = derivativeParams;
        _;
    }

    function test_derivative_invalidParams()
        public
        givenAuctionHouseHasBalance(payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeParamsAreInvalid
    {
        // Expect revert while decoding parameters
        vm.expectRevert();

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_derivative_insufficientBalance_reverts() public givenAuctionHasDerivative {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_derivative()
        public
        givenAuctionHouseHasBalance(payoutAmount)
        givenAuctionHasDerivative
    {
        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);

        // Check balances of the derivative token
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(USER, derivativeTokenId),
            0,
            "derivative token: user balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(OWNER, derivativeTokenId),
            0,
            "derivative token: owner balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(
                address(auctionHouse), derivativeTokenId
            ),
            0,
            "derivative token: auctionHouse balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(address(hook), derivativeTokenId),
            0,
            "derivative token: hook balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(RECIPIENT, derivativeTokenId),
            payoutAmount,
            "derivative token: recipient balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(
                address(mockDerivativeModule), derivativeTokenId
            ),
            0,
            "derivative token: derivative module balance mismatch"
        );

        // Check balances of payout token
        assertEq(payoutToken.balanceOf(USER), 0, "payout token: user balance mismatch");
        assertEq(payoutToken.balanceOf(OWNER), 0, "payout token: owner balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(auctionHouse)),
            0,
            "payout token: auctionHouse balance mismatch"
        );
        assertEq(payoutToken.balanceOf(address(hook)), 0, "payout token: hook balance mismatch");
        assertEq(payoutToken.balanceOf(RECIPIENT), 0, "payout token: recipient balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            payoutAmount,
            "payout token: derivative module balance mismatch"
        );
    }

    function test_derivative_wrapped()
        public
        givenAuctionHouseHasBalance(payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeIsWrapped
    {
        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);

        // Check balances of the wrapped derivative token
        assertEq(
            wrappedDerivative.balanceOf(USER), 0, "wrapped derivative token: user balance mismatch"
        );
        assertEq(
            wrappedDerivative.balanceOf(OWNER),
            0,
            "wrapped derivative token: owner balance mismatch"
        );
        assertEq(
            wrappedDerivative.balanceOf(address(auctionHouse)),
            0,
            "wrapped derivative token: auctionHouse balance mismatch"
        );
        assertEq(
            wrappedDerivative.balanceOf(address(hook)),
            0,
            "wrapped derivative token: hook balance mismatch"
        );
        assertEq(
            wrappedDerivative.balanceOf(RECIPIENT),
            payoutAmount,
            "wrapped derivative token: recipient balance mismatch"
        );
        assertEq(
            wrappedDerivative.balanceOf(address(mockDerivativeModule)),
            0,
            "wrapped derivative token: derivative module balance mismatch"
        );

        // Check balances of the derivative token
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(USER, derivativeTokenId),
            0,
            "derivative token: user balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(OWNER, derivativeTokenId),
            0,
            "derivative token: owner balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(
                address(auctionHouse), derivativeTokenId
            ),
            0,
            "derivative token: auctionHouse balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(address(hook), derivativeTokenId),
            0,
            "derivative token: hook balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(RECIPIENT, derivativeTokenId),
            0, // No raw derivative
            "derivative token: recipient balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(
                address(mockDerivativeModule), derivativeTokenId
            ),
            0,
            "derivative token: derivative module balance mismatch"
        );

        // Check balances of payout token
        assertEq(payoutToken.balanceOf(USER), 0, "payout token: user balance mismatch");
        assertEq(payoutToken.balanceOf(OWNER), 0, "payout token: owner balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(auctionHouse)),
            0,
            "payout token: auctionHouse balance mismatch"
        );
        assertEq(payoutToken.balanceOf(address(hook)), 0, "payout token: hook balance mismatch");
        assertEq(payoutToken.balanceOf(RECIPIENT), 0, "payout token: recipient balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            payoutAmount,
            "payout token: derivative module balance mismatch"
        );
    }

    function test_derivative_wrapped_invalidParams()
        public
        givenAuctionHouseHasBalance(payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeIsWrapped
        givenDerivativeParamsAreInvalid
    {
        // Expect revert while decoding parameters
        vm.expectRevert();

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_derivative_condenser_invalidParams_reverts()
        public
        givenAuctionHouseHasBalance(payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeHasCondenser
        givenDerivativeParamsAreInvalid
    {
        // Expect revert while decoding parameters
        vm.expectRevert();

        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);
    }

    function test_derivative_condenser()
        public
        givenAuctionHouseHasBalance(payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeHasCondenser
    {
        // Call
        vm.prank(USER);
        auctionHouse.sendPayout(lotId, RECIPIENT, payoutAmount, routingParams, auctionOutput);

        // Check balances of the derivative token
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(USER, derivativeTokenId),
            0,
            "user balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(OWNER, derivativeTokenId),
            0,
            "owner balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(
                address(auctionHouse), derivativeTokenId
            ),
            0,
            "auctionHouse balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(address(hook), derivativeTokenId),
            0,
            "hook balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(RECIPIENT, derivativeTokenId),
            payoutAmount * auctionOutputMultiplier, // Condenser multiplies the payout
            "recipient balance mismatch"
        );
        assertEq(
            mockDerivativeModule.derivativeToken().balanceOf(
                address(mockDerivativeModule), derivativeTokenId
            ),
            0,
            "derivative module balance mismatch"
        );

        // Check balances of payout token
        assertEq(payoutToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(payoutToken.balanceOf(OWNER), 0, "owner balance mismatch");
        assertEq(payoutToken.balanceOf(address(auctionHouse)), 0, "auctionHouse balance mismatch");
        assertEq(payoutToken.balanceOf(address(hook)), 0, "hook balance mismatch");
        assertEq(payoutToken.balanceOf(RECIPIENT), 0, "recipient balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            payoutAmount,
            "derivative module balance mismatch"
        );
    }
}
