/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {MockHook} from "test/modules/Auction/MockHook.sol";
import {MockAuctionHouse} from "test/AuctionHouse/MockAuctionHouse.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {Router} from "src/AuctionHouse.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

contract SendPaymentTest is Test, Permit2User {
    MockAuctionHouse internal auctionHouse;

    address internal constant PROTOCOL = address(0x1);

    address internal USER = address(0x2);
    address internal OWNER = address(0x3);

    // Function parameters
    uint96 internal lotId = 1;
    uint256 internal paymentAmount = 1e18;
    MockFeeOnTransferERC20 internal quoteToken;
    MockHook internal hook;

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        auctionHouse = new MockAuctionHouse(PROTOCOL, _PERMIT2_ADDRESS);

        quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);
        quoteToken.setTransferFee(0);
    }

    // [X] given the auction has hooks defined
    //  [X] it transfers the payment amount to the hook
    // [X] given the auction does not have hooks defined
    //  [X] it transfers the payment amount to the owner

    modifier givenAuctionHasHook() {
        hook = new MockHook(address(quoteToken), address(0));

        // Set the addresses to track
        address[] memory addresses = new address[](4);
        addresses[0] = address(USER);
        addresses[1] = address(OWNER);
        addresses[2] = address(auctionHouse);
        addresses[3] = address(hook);

        hook.setBalanceAddresses(addresses);
        _;
    }

    modifier givenRouterHasBalance(uint256 amount_) {
        quoteToken.mint(address(auctionHouse), amount_);
        _;
    }

    function test_givenAuctionHasHook()
        public
        givenAuctionHasHook
        givenRouterHasBalance(paymentAmount)
    {
        // Call
        vm.prank(USER);
        auctionHouse.sendPayment(OWNER, paymentAmount, quoteToken, hook);

        // Check balances
        assertEq(quoteToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(quoteToken.balanceOf(OWNER), 0, "owner balance mismatch");
        assertEq(quoteToken.balanceOf(address(auctionHouse)), 0, "auctionHouse balance mismatch");
        assertEq(quoteToken.balanceOf(address(hook)), paymentAmount, "hook balance mismatch");

        // Hooks not called
        assertEq(hook.preHookCalled(), false, "pre hook called");
        assertEq(hook.midHookCalled(), false, "mid hook called");
        assertEq(hook.postHookCalled(), false, "post hook called");
    }

    function test_givenAuctionHasNoHook() public givenRouterHasBalance(paymentAmount) {
        // Call
        vm.prank(USER);
        auctionHouse.sendPayment(OWNER, paymentAmount, quoteToken, hook);

        // Check balances
        assertEq(quoteToken.balanceOf(USER), 0, "user balance mismatch");
        assertEq(quoteToken.balanceOf(OWNER), paymentAmount, "owner balance mismatch");
        assertEq(quoteToken.balanceOf(address(auctionHouse)), 0, "auctionHouse balance mismatch");
    }
}
