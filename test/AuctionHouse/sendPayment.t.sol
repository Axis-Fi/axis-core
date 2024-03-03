/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {MockHook} from "test/modules/Auction/MockHook.sol";
import {MockAuctionHouse} from "test/AuctionHouse/MockAuctionHouse.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

contract SendPaymentTest is Test, Permit2User {
    MockAuctionHouse internal _auctionHouse;

    address internal constant _PROTOCOL = address(0x1);

    address internal constant _USER = address(0x2);
    address internal constant _SELLER = address(0x3);

    // Function parameters
    uint256 internal _paymentAmount = 1e18;
    MockFeeOnTransferERC20 internal _quoteToken;
    MockHook internal _hook;

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        _auctionHouse = new MockAuctionHouse(_PROTOCOL, _PERMIT2_ADDRESS);

        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);
        _quoteToken.setTransferFee(0);
    }

    // [X] given the auction has hooks defined
    //  [X] it transfers the payment amount to the _hook
    // [X] given the auction does not have hooks defined
    //  [X] it transfers the payment amount to the seller

    modifier givenAuctionHasHook() {
        _hook = new MockHook(address(_quoteToken), address(0));

        // Set the addresses to track
        address[] memory addresses = new address[](4);
        addresses[0] = address(_USER);
        addresses[1] = address(_SELLER);
        addresses[2] = address(_auctionHouse);
        addresses[3] = address(_hook);

        _hook.setBalanceAddresses(addresses);
        _;
    }

    modifier givenRouterHasBalance(uint256 amount_) {
        _quoteToken.mint(address(_auctionHouse), amount_);
        _;
    }

    function test_givenAuctionHasHook()
        public
        givenAuctionHasHook
        givenRouterHasBalance(_paymentAmount)
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayment(_SELLER, _paymentAmount, _quoteToken, _hook);

        // Check balances
        assertEq(_quoteToken.balanceOf(_USER), 0, "user balance mismatch");
        assertEq(_quoteToken.balanceOf(_SELLER), 0, "seller balance mismatch");
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "_auctionHouse balance mismatch");
        assertEq(_quoteToken.balanceOf(address(_hook)), _paymentAmount, "_hook balance mismatch");

        // Hooks not called
        assertEq(_hook.preHookCalled(), false, "pre _hook called");
        assertEq(_hook.midHookCalled(), false, "mid _hook called");
        assertEq(_hook.postHookCalled(), false, "post _hook called");
    }

    function test_givenAuctionHasNoHook() public givenRouterHasBalance(_paymentAmount) {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayment(_SELLER, _paymentAmount, _quoteToken, _hook);

        // Check balances
        assertEq(_quoteToken.balanceOf(_USER), 0, "user balance mismatch");
        assertEq(_quoteToken.balanceOf(_SELLER), _paymentAmount, "seller balance mismatch");
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "_auctionHouse balance mismatch");
    }
}
