/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {MockHook} from "test/modules/Auction/MockHook.sol";
import {ConcreteRouter} from "test/Router/ConcreteRouter.sol";
import {MockFeeOnTransferERC20} from "test/Router/MockFeeOnTransferERC20.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {Router} from "src/AuctionHouse.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

contract SendPayoutTest is Test, Permit2User {
    ConcreteRouter internal router;

    address internal constant PROTOCOL = address(0x1);

    address internal USER = address(0x2);
    address internal OWNER = address(0x3);
    address internal RECIPIENT = address(0x4);

    // Function parameters
    uint256 internal lotId = 1;
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

    modifier givenTokenTakesFeeOnTransfer() {
        payoutToken.setTransferFee(1000);
        _;
    }

    modifier givenRouterHasBalance(uint256 amount_) {
        payoutToken.mint(address(router), amount_);
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
    //  [X] it succeeds - transfers the payout from the router to the recipient

    modifier givenAuctionHasHook() {
        hook = new MockHook(address(0), address(payoutToken));

        // Set the addresses to track
        address[] memory addresses = new address[](5);
        addresses[0] = USER;
        addresses[1] = OWNER;
        addresses[2] = address(router);
        addresses[3] = address(hook);
        addresses[4] = RECIPIENT;

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
        givenRouterHasBalance(payoutAmount)
    {
        // Expect revert
        vm.expectRevert("revert");

        // Call
        vm.prank(USER);
        router.sendPayout(lotId, RECIPIENT, payoutAmount, payoutToken, hook);
    }

    function test_hooks_feeOnTransfer_reverts()
        public
        givenAuctionHasHook
        givenRouterHasBalance(payoutAmount)
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Router.UnsupportedToken.selector, address(payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.sendPayout(lotId, RECIPIENT, payoutAmount, payoutToken, hook);
    }

    function test_hooks() public givenAuctionHasHook givenRouterHasBalance(payoutAmount) {
        // Call
        vm.prank(USER);
        router.sendPayout(lotId, RECIPIENT, payoutAmount, payoutToken, hook);

        // Check balances
        assertEq(payoutToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(payoutToken.balanceOf(OWNER), 0, "owner balance mismatch");
        assertEq(payoutToken.balanceOf(address(router)), 0, "router balance mismatch");
        assertEq(payoutToken.balanceOf(address(hook)), 0, "hook balance mismatch");
        assertEq(payoutToken.balanceOf(RECIPIENT), payoutAmount, "recipient balance mismatch");

        // Check the hook was called at the right time
        assertEq(hook.preHookCalled(), false, "pre hook mismatch");
        assertEq(hook.midHookCalled(), false, "mid hook mismatch");
        assertEq(hook.postHookCalled(), true, "post hook mismatch");
        assertEq(hook.postHookBalances(payoutToken, USER), 0, "post hook user balance mismatch");
        assertEq(hook.postHookBalances(payoutToken, OWNER), 0, "post hook owner balance mismatch");
        assertEq(
            hook.postHookBalances(payoutToken, address(router)),
            0,
            "post hook router balance mismatch"
        );
        assertEq(
            hook.postHookBalances(payoutToken, address(hook)), 0, "post hook hook balance mismatch"
        );
        assertEq(
            hook.postHookBalances(payoutToken, RECIPIENT),
            payoutAmount,
            "post hook recipient balance mismatch"
        );
    }

    // ========== Non-hooks flow ========== //

    // [X] given the auction does not have hooks defined
    //  [X] given transferring the payout token would result in a lesser amount being received
    //   [X] it reverts
    //  [X] it succeeds - transfers the payout from the router to the recipient

    function test_noHooks_feeOnTransfer_reverts()
        public
        givenRouterHasBalance(payoutAmount)
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Router.UnsupportedToken.selector, address(payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.sendPayout(lotId, RECIPIENT, payoutAmount, payoutToken, hook);
    }

    function test_noHooks() public givenRouterHasBalance(payoutAmount) {
        // Call
        vm.prank(USER);
        router.sendPayout(lotId, RECIPIENT, payoutAmount, payoutToken, hook);

        // Check balances
        assertEq(payoutToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(payoutToken.balanceOf(OWNER), 0, "owner balance mismatch");
        assertEq(payoutToken.balanceOf(address(router)), 0, "router balance mismatch");
        assertEq(payoutToken.balanceOf(address(hook)), 0, "hook balance mismatch");
        assertEq(payoutToken.balanceOf(RECIPIENT), payoutAmount, "recipient balance mismatch");
    }
}
