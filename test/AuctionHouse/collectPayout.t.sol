/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Transfer} from "src/lib/Transfer.sol";

import {MockHook} from "test/modules/Auction/MockHook.sol";
import {MockAuctionHouse} from "test/AuctionHouse/MockAuctionHouse.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {Veecode, wrapVeecode, toVeecode, toKeycode} from "src/modules/Modules.sol";

contract CollectPayoutTest is Test, Permit2User {
    MockAuctionHouse internal auctionHouse;
    MockDerivativeModule internal mockDerivativeModule;

    address internal constant PROTOCOL = address(0x1);

    address internal USER = address(0x2);
    address internal OWNER = address(0x3);

    // Function parameters
    uint96 internal lotId = 1;
    uint256 internal paymentAmount = 1e18;
    uint256 internal payoutAmount = 10e18;
    MockFeeOnTransferERC20 internal quoteToken;
    MockFeeOnTransferERC20 internal payoutToken;
    MockHook internal hook;
    Veecode internal derivativeReference;
    bytes internal derivativeParams;
    bool internal wrapDerivative;

    Auctioneer.Routing internal routingParams;

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        auctionHouse = new MockAuctionHouse(PROTOCOL, _PERMIT2_ADDRESS);
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));

        quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);
        quoteToken.setTransferFee(0);

        payoutToken = new MockFeeOnTransferERC20("Payout Token", "PAYOUT", 18);
        payoutToken.setTransferFee(0);

        derivativeReference = toVeecode(bytes7(""));
        derivativeParams = bytes("");
        wrapDerivative = false;

        routingParams = Auctioneer.Routing({
            auctionReference: wrapVeecode(toKeycode("MOCK"), 1),
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

    modifier givenOwnerHasBalance(uint256 amount_) {
        payoutToken.mint(OWNER, amount_);
        _;
    }

    modifier givenOwnerHasApprovedRouter() {
        vm.prank(OWNER);
        payoutToken.approve(address(auctionHouse), type(uint256).max);
        _;
    }

    modifier givenTokenTakesFeeOnTransfer() {
        payoutToken.setTransferFee(1000);
        _;
    }

    // ========== Hooks flow ========== //

    // [X] given the auction has hooks defined
    //  [X] when the mid hook reverts
    //   [X] it reverts
    //  [X] when the mid hook does not revert
    //   [X] given the invariant is violated
    //    [X] it reverts
    //   [X] given the invariant is not violated
    //    [X] it succeeds

    modifier givenAuctionHasHook() {
        hook = new MockHook(address(quoteToken), address(payoutToken));
        routingParams.hooks = hook;

        // Set the addresses to track
        address[] memory addresses = new address[](5);
        addresses[0] = USER;
        addresses[1] = OWNER;
        addresses[2] = address(auctionHouse);
        addresses[3] = address(hook);
        addresses[4] = address(mockDerivativeModule);

        hook.setBalanceAddresses(addresses);
        _;
    }

    modifier givenMidHookReverts() {
        hook.setMidHookReverts(true);
        _;
    }

    modifier whenMidHookBreaksInvariant() {
        hook.setMidHookMultiplier(9000);
        _;
    }

    modifier givenHookHasBalance(uint256 amount_) {
        payoutToken.mint(address(hook), amount_);
        _;
    }

    modifier givenHookHasApprovedRouter() {
        vm.prank(address(hook));
        payoutToken.approve(address(auctionHouse), type(uint256).max);
        _;
    }

    function test_givenAuctionHasHook_whenMidHookReverts_reverts()
        public
        givenAuctionHasHook
        givenMidHookReverts
    {
        // Expect revert
        vm.expectRevert("revert");

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_givenAuctionHasHook_whenMidHookBreaksInvariant_reverts()
        public
        givenAuctionHasHook
        givenHookHasBalance(payoutAmount)
        givenHookHasApprovedRouter
        whenMidHookBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_givenAuctionHasHook_feeOnTransfer_reverts()
        public
        givenAuctionHasHook
        givenHookHasBalance(payoutAmount)
        givenHookHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_givenAuctionHasHook()
        public
        givenAuctionHasHook
        givenHookHasBalance(payoutAmount)
        givenHookHasApprovedRouter
    {
        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);

        // Expect the hook to be called prior to any transfer of the payout token
        assertEq(hook.midHookCalled(), true);
        assertEq(hook.midHookBalances(payoutToken, OWNER), 0, "mid-hook: owner balance mismatch");
        assertEq(hook.midHookBalances(payoutToken, USER), 0, "mid-hook: user balance mismatch");
        assertEq(
            hook.midHookBalances(payoutToken, address(auctionHouse)),
            0,
            "mid-hook: auctionHouse balance mismatch"
        );
        assertEq(
            hook.midHookBalances(payoutToken, address(hook)),
            payoutAmount,
            "mid-hook: hook balance mismatch"
        );
        assertEq(
            hook.midHookBalances(payoutToken, address(mockDerivativeModule)),
            0,
            "mid-hook: derivativeModule balance mismatch"
        );

        // Expect the other hooks not to be called
        assertEq(hook.preHookCalled(), false);
        assertEq(hook.postHookCalled(), false);

        // Expect payout token balance to be transferred to the auctionHouse
        assertEq(payoutToken.balanceOf(OWNER), 0, "owner balance mismatch");
        assertEq(payoutToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(auctionHouse)),
            payoutAmount,
            "auctionHouse balance mismatch"
        );
        assertEq(payoutToken.balanceOf(address(hook)), 0, "hook balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            0,
            "derivativeModule balance mismatch"
        );
    }

    // ========== Non-hooks flow ========== //

    // [X] given the auction does not have hooks defined
    //  [X] given the auction owner has insufficient balance of the payout token
    //   [X] it reverts
    //  [X] given the auction owner has not approved the auctionHouse to transfer the payout token
    //   [X] it reverts
    //  [X] given transferring the payout token would result in a lesser amount being received
    //   [X] it reverts
    //  [X] it succeeds

    function test_insufficientBalance_reverts() public {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_insufficientAllowance_reverts() public givenOwnerHasBalance(payoutAmount) {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_feeOnTransfer_reverts()
        public
        givenOwnerHasBalance(payoutAmount)
        givenOwnerHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_success() public givenOwnerHasBalance(payoutAmount) givenOwnerHasApprovedRouter {
        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);

        // Expect payout token balance to be transferred to the auctionHouse
        assertEq(payoutToken.balanceOf(OWNER), 0);
        assertEq(payoutToken.balanceOf(USER), 0);
        assertEq(payoutToken.balanceOf(address(auctionHouse)), payoutAmount);
        assertEq(payoutToken.balanceOf(address(hook)), 0);
        assertEq(payoutToken.balanceOf(address(mockDerivativeModule)), 0);
    }

    // ========== Derivative flow ========== //

    // [X] given the auction has a derivative defined
    //  [X] given the auction has hooks defined
    //   [X] given the hook breaks the invariant
    //    [X] it reverts
    //   [X] it succeeds - base token is transferred to the auction house, mid hook is called before transfer
    //  [X] given the auction does not have hooks defined
    //   [X] given the auction owner has insufficient balance of the payout token
    //    [X] it reverts
    //   [X] given the auction owner has not approved the auctionHouse to transfer the payout token
    //    [X] it reverts
    //   [X] given transferring the payout token would result in a lesser amount being received
    //    [X] it reverts
    //   [X] it succeeds - base token is transferred to the auction house

    modifier givenAuctionHasDerivative() {
        // Install the derivative module
        auctionHouse.installModule(mockDerivativeModule);

        // Update parameters
        derivativeReference = mockDerivativeModule.VEECODE();
        routingParams.derivativeReference = derivativeReference;
        _;
    }

    function test_derivative_hasHook_whenHookBreaksInvariant_reverts()
        public
        givenAuctionHasDerivative
        givenAuctionHasHook
        givenHookHasBalance(payoutAmount)
        givenHookHasApprovedRouter
        whenMidHookBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_derivative_hasHook_success()
        public
        givenAuctionHasDerivative
        givenAuctionHasHook
        givenHookHasBalance(payoutAmount)
        givenHookHasApprovedRouter
    {
        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);

        // Expect payout token balance to be transferred to the derivative module
        assertEq(payoutToken.balanceOf(OWNER), 0, "payout token: owner balance mismatch");
        assertEq(payoutToken.balanceOf(USER), 0, "payout token: user balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(auctionHouse)),
            payoutAmount,
            "payout token: auctionHouse balance mismatch"
        );
        assertEq(payoutToken.balanceOf(address(hook)), 0, "payout token: hook balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            0,
            "payout token: derivativeModule balance mismatch"
        );

        // Expect the hook to be called prior to any transfer of the payout token
        assertEq(hook.midHookCalled(), true);
        assertEq(hook.midHookBalances(payoutToken, OWNER), 0, "mid-hook: owner balance mismatch");
        assertEq(hook.midHookBalances(payoutToken, USER), 0, "mid-hook: user balance mismatch");
        assertEq(
            hook.midHookBalances(payoutToken, address(auctionHouse)),
            0,
            "mid-hook: auctionHouse balance mismatch"
        );
        assertEq(
            hook.midHookBalances(payoutToken, address(hook)),
            payoutAmount,
            "mid-hook: hook balance mismatch"
        );
        assertEq(
            hook.midHookBalances(payoutToken, address(mockDerivativeModule)),
            0,
            "mid-hook: derivativeModule balance mismatch"
        );

        // Expect the other hooks not to be called
        assertEq(hook.preHookCalled(), false);
        assertEq(hook.postHookCalled(), false);
    }

    function test_derivative_insufficientBalance_reverts() public givenAuctionHasDerivative {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_derivative_insufficientAllowance_reverts()
        public
        givenAuctionHasDerivative
        givenOwnerHasBalance(payoutAmount)
    {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_derivative_feeOnTransfer_reverts()
        public
        givenAuctionHasDerivative
        givenOwnerHasBalance(payoutAmount)
        givenOwnerHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);
    }

    function test_derivative_success()
        public
        givenAuctionHasDerivative
        givenOwnerHasBalance(payoutAmount)
        givenOwnerHasApprovedRouter
    {
        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);

        // Expect payout token balance to be transferred to the auction house
        assertEq(payoutToken.balanceOf(OWNER), 0, "payout token: owner balance mismatch");
        assertEq(payoutToken.balanceOf(USER), 0, "payout token: user balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(auctionHouse)),
            payoutAmount,
            "payout token: auctionHouse balance mismatch"
        );
        assertEq(payoutToken.balanceOf(address(hook)), 0, "payout token: hook balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            0,
            "payout token: derivativeModule balance mismatch"
        );
    }

    // ========== Prefunding flow ========== //

    // [X] given the auction is pre-funded
    //  [X] it does not transfer the base token to the auction house

    modifier givenAuctionIsPrefunded(uint256 amount_) {
        routingParams.prefunding = amount_;
        _;
    }

    modifier givenAuctionHouseHasPayoutTokenBalance(uint256 amount_) {
        payoutToken.mint(address(auctionHouse), amount_);
        _;
    }

    function test_prefunded()
        public
        givenAuctionIsPrefunded(payoutAmount)
        givenAuctionHouseHasPayoutTokenBalance(payoutAmount)
    {
        // Assert previous balance
        assertEq(
            payoutToken.balanceOf(address(auctionHouse)),
            payoutAmount,
            "payout token: auctionHouse balance mismatch"
        );

        // Call
        vm.prank(USER);
        auctionHouse.collectPayout(lotId, paymentAmount, payoutAmount, routingParams);

        // Check balances
        assertEq(payoutToken.balanceOf(OWNER), 0, "payout token: owner balance mismatch");
        assertEq(payoutToken.balanceOf(USER), 0, "payout token: user balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(auctionHouse)),
            payoutAmount,
            "payout token: auctionHouse balance mismatch"
        );
        assertEq(payoutToken.balanceOf(address(hook)), 0, "payout token: hook balance mismatch");
        assertEq(
            payoutToken.balanceOf(address(mockDerivativeModule)),
            0,
            "payout token: derivativeModule balance mismatch"
        );
    }
}
