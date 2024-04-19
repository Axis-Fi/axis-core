// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {MockCallback} from "test/callbacks/MockCallback.sol";
import {MockAuctionHouse} from "test/AuctionHouse/MockAuctionHouse.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

contract SendPaymentTest is Test, Permit2User {
    MockAuctionHouse internal _auctionHouse;

    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _USER = address(0x4);

    // Function parameters
    uint256 internal _paymentAmount = 1e18;
    MockFeeOnTransferERC20 internal _quoteToken;
    MockCallback internal _callback;
    bool internal _callbackReceiveQuoteTokens;

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        MockAuctionHouse mockAuctionHouse = new MockAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = MockAuctionHouse(address(0x000000000000000000000000000000000000000A));
        vm.etch(address(_auctionHouse), address(mockAuctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);
        _quoteToken.setTransferFee(0);
    }

    // [X] given the auction has hooks defined
    //  [X] it transfers the payment amount to the _callback
    // [X] given the auction does not have hooks defined
    //  [X] it transfers the payment amount to the seller

    modifier givenCallbackReceivesQuoteTokens() {
        _callbackReceiveQuoteTokens = true;
        _;
    }

    modifier givenAuctionHasCallback() {
        bytes32 salt;
        if (_callbackReceiveQuoteTokens) {
            // 0x02
            // cast create2 -s 02 -i $(cat ./bytecode/MockCallback02.bin)
            salt = bytes32(0x6ff950930aaebd51d12fac0a23c6f63dbfac64e27d7f77466a79c3975d1bfb2c);
        } else {
            // 0x00
            // cast create2 -s 00 -i $(cat ./bytecode/MockCallback00.bin)
            salt = bytes32(0xb60aee9874a4c3333bacfe11a4589854989ccd71c63a80b731385bcf20470eef);
        }

        vm.broadcast(); // required for CREATE2 address to work correctly. doesn't do anything in a test
        _callback = new MockCallback{salt: salt}(
            address(_auctionHouse),
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onClaimProceeds: false,
                receiveQuoteTokens: _callbackReceiveQuoteTokens,
                sendBaseTokens: false
            }),
            _SELLER
        );
        _;
    }

    modifier givenRouterHasBalance(uint256 amount_) {
        _quoteToken.mint(address(_auctionHouse), amount_);
        _;
    }

    function test_givenAuctionHasCallback_givenReceivesTokens()
        public
        givenCallbackReceivesQuoteTokens
        givenAuctionHasCallback
        givenRouterHasBalance(_paymentAmount)
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayment(_SELLER, _paymentAmount, _quoteToken, _callback);

        // Check balances
        assertEq(_quoteToken.balanceOf(_USER), 0, "user balance mismatch");
        assertEq(_quoteToken.balanceOf(_SELLER), 0, "seller balance mismatch");
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "_auctionHouse balance mismatch");
        assertEq(
            _quoteToken.balanceOf(address(_callback)), _paymentAmount, "_callback balance mismatch"
        );
    }

    function test_givenAuctionHasCallback()
        public
        givenAuctionHasCallback
        givenRouterHasBalance(_paymentAmount)
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayment(_SELLER, _paymentAmount, _quoteToken, _callback);

        // Check balances
        assertEq(_quoteToken.balanceOf(_USER), 0, "user balance mismatch");
        assertEq(_quoteToken.balanceOf(_SELLER), _paymentAmount, "seller balance mismatch");
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "_auctionHouse balance mismatch");
        assertEq(_quoteToken.balanceOf(address(_callback)), 0, "_callback balance mismatch");
    }

    function test_givenAuctionHasNoCallback() public givenRouterHasBalance(_paymentAmount) {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayment(_SELLER, _paymentAmount, _quoteToken, _callback);

        // Check balances
        assertEq(_quoteToken.balanceOf(_USER), 0, "user balance mismatch");
        assertEq(_quoteToken.balanceOf(_SELLER), _paymentAmount, "seller balance mismatch");
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "_auctionHouse balance mismatch");
    }
}
