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
    uint256 internal amount = 10e18;
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
        payoutToken.setTransferFee(1e18);
        _;
    }

    // ========== Hooks flow ========== //

    // [ ] given the auction has hooks defined
    //  [X] when the mid hook reverts
    //   [X] it reverts
    //  [ ] when the mid hook does not revert
    //   [ ] given the invariant is violated
    //    [ ] it reverts
    //   [X] given the invariant is not violated - TODO define invariant
    //    [X] it succeeds

    modifier givenAuctionHasHook() {
        hook = new MockHook();
        _;
    }

    modifier givenMidHookReverts() {
        hook.setMidHookReverts(true);
        _;
    }

    modifier whenMidHookBalanceIsRecorded() {
        hook.setMidHookValues(address(payoutToken), OWNER);
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
        router.collectPayout(lotId, amount, payoutToken, hook);
    }

    function test_givenAuctionHasHook()
        public
        givenAuctionHasHook
        givenOwnerHasBalance(amount)
        givenOwnerHasApprovedRouter
        whenMidHookBalanceIsRecorded
    {
        // Call
        vm.prank(USER);
        router.collectPayout(lotId, amount, payoutToken, hook);

        // Expect payout token balance to be transferred to the router
        assertEq(payoutToken.balanceOf(address(router)), amount);
        assertEq(payoutToken.balanceOf(OWNER), 0);
        assertEq(payoutToken.balanceOf(address(hook)), 0);

        // Expect the hook to be called
        assertEq(hook.midHookCalled(), true);
        assertEq(hook.midHookBalance(), amount);

        // Expect the other hooks not to be called
        assertEq(hook.preHookCalled(), false);
        assertEq(hook.postHookCalled(), false);
    }
}
