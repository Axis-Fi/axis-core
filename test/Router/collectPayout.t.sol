/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {MockHook} from "test/modules/Auction/MockHook.sol";
import {ConcreteRouter} from "test/Router/ConcreteRouter.sol";
import {MockFeeOnTransferERC20} from "test/Router/MockFeeOnTransferERC20.sol";
import {Permit2Clone} from "test/lib/permit2/Permit2Clone.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {IPermit2} from "src/lib/permit2/interfaces/IPermit2.sol";
import {Router} from "src/AuctionHouse.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

contract CollectPayoutTest is Test, Permit2User {
    ConcreteRouter internal router;

    address internal constant PROTOCOL = address(0x1);

    address internal USER = address(0x2);
    address internal OWNER = address(0x3);

    // Function parameters
    uint256 internal lotId = 1;
    uint256 internal paymentAmount = 1e18;
    uint256 internal payoutAmount = 10e18;
    MockFeeOnTransferERC20 internal payoutToken;
    MockHook internal hook;

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        router = new ConcreteRouter(PROTOCOL, _PERMIT2_ADDRESS);

        payoutToken = new MockFeeOnTransferERC20("Payout Token", "PAYOUT", 18);
        payoutToken.setTransferFee(0);
    }

    modifier givenOwnerHasBalance(uint256 amount_) {
        payoutToken.mint(OWNER, amount_);
        _;
    }

    modifier givenOwnerHasApprovedRouter() {
        vm.prank(OWNER);
        payoutToken.approve(address(router), type(uint256).max);
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
        hook = new MockHook(address(0), address(payoutToken));

        // Set the addresses to track
        address[] memory addresses = new address[](4);
        addresses[0] = USER;
        addresses[1] = OWNER;
        addresses[2] = address(router);
        addresses[3] = address(hook);

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
        payoutToken.approve(address(router), type(uint256).max);
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
        router.collectPayout(lotId, OWNER, paymentAmount, payoutAmount, payoutToken, hook);
    }

    function test_givenAuctionHasHook_whenMidHookBreaksInvariant_reverts()
        public
        givenAuctionHasHook
        givenHookHasBalance(payoutAmount)
        givenHookHasApprovedRouter
        whenMidHookBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Router.InvalidHook.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayout(lotId, OWNER, paymentAmount, payoutAmount, payoutToken, hook);
    }

    function test_givenAuctionHasHook_feeOnTransfer_reverts()
        public
        givenAuctionHasHook
        givenHookHasBalance(payoutAmount)
        givenHookHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Router.InvalidHook.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayout(lotId, OWNER, paymentAmount, payoutAmount, payoutToken, hook);
    }

    function test_givenAuctionHasHook()
        public
        givenAuctionHasHook
        givenHookHasBalance(payoutAmount)
        givenHookHasApprovedRouter
    {
        // Call
        vm.prank(USER);
        router.collectPayout(lotId, OWNER, paymentAmount, payoutAmount, payoutToken, hook);

        // Expect the hook to be called prior to any transfer of the payout token
        assertEq(hook.midHookCalled(), true);
        assertEq(hook.midHookBalances(payoutToken, OWNER), 0, "mid-hook: owner balance mismatch");
        assertEq(hook.midHookBalances(payoutToken, USER), 0, "mid-hook: user balance mismatch");
        assertEq(
            hook.midHookBalances(payoutToken, address(router)),
            0,
            "mid-hook: router balance mismatch"
        );
        assertEq(
            hook.midHookBalances(payoutToken, address(hook)),
            payoutAmount,
            "mid-hook: hook balance mismatch"
        );

        // Expect the other hooks not to be called
        assertEq(hook.preHookCalled(), false);
        assertEq(hook.postHookCalled(), false);

        // Expect payout token balance to be transferred to the router
        assertEq(payoutToken.balanceOf(OWNER), 0, "owner balance mismatch");
        assertEq(payoutToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(payoutToken.balanceOf(address(router)), payoutAmount, "router balance mismatch");
        assertEq(payoutToken.balanceOf(address(hook)), 0, "hook balance mismatch");
    }

    // ========== Non-hooks flow ========== //

    // [X] given the auction does not have hooks defined
    //  [X] given the auction owner has insufficient balance of the payout token
    //   [X] it reverts
    //  [X] given the auction owner has not approved the router to transfer the payout token
    //   [X] it reverts
    //  [X] given transferring the payout token would result in a lesser amount being received
    //   [X] it reverts
    //  [X] it succeeds

    function test_insufficientBalance_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Router.InsufficientBalance.selector, address(payoutToken), payoutAmount
        );
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayout(lotId, OWNER, paymentAmount, payoutAmount, payoutToken, hook);
    }

    function test_insufficientAllowance_reverts() public givenOwnerHasBalance(payoutAmount) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Router.InsufficientAllowance.selector,
            address(payoutToken),
            address(router),
            payoutAmount
        );
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayout(lotId, OWNER, paymentAmount, payoutAmount, payoutToken, hook);
    }

    function test_feeOnTransfer_reverts()
        public
        givenOwnerHasBalance(payoutAmount)
        givenOwnerHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Router.UnsupportedToken.selector, address(payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayout(lotId, OWNER, paymentAmount, payoutAmount, payoutToken, hook);
    }

    function test_success() public givenOwnerHasBalance(payoutAmount) givenOwnerHasApprovedRouter {
        // Call
        vm.prank(USER);
        router.collectPayout(lotId, OWNER, paymentAmount, payoutAmount, payoutToken, hook);

        // Expect payout token balance to be transferred to the router
        assertEq(payoutToken.balanceOf(OWNER), 0);
        assertEq(payoutToken.balanceOf(USER), 0);
        assertEq(payoutToken.balanceOf(address(router)), payoutAmount);
        assertEq(payoutToken.balanceOf(address(hook)), 0);
    }

    // ========== Derivative flow ========== //

    // [ ] given the auction has a derivative defined
    //  [ ] given the auction has hooks defined
    //   [ ] given the hook breaks the invariant
    //    [ ] it reverts
    //   [ ] it succeeds - derivative is minted to the router, mid hook is called before minting
    //  [ ] given the auction does not have hooks defined
    //   [ ] it succeeds - derivative is minted to the router
}
