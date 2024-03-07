/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Transfer} from "src/lib/Transfer.sol";

import {MockHook} from "test/modules/Auction/MockHook.sol";
import {MockAuctionHouse} from "test/AuctionHouse/MockAuctionHouse.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {Veecode, wrapVeecode, toVeecode, toKeycode} from "src/modules/Modules.sol";

contract CollectPayoutTest is Test, Permit2User {
    MockAuctionHouse internal _auctionHouse;
    MockDerivativeModule internal _mockDerivativeModule;

    address internal constant _PROTOCOL = address(0x1);

    address internal constant _USER = address(0x2);
    address internal constant _SELLER = address(0x3);

    // Function parameters
    uint96 internal _lotId = 1;
    uint256 internal _paymentAmount = 1e18;
    uint256 internal _payoutAmount = 10e18;
    MockFeeOnTransferERC20 internal _quoteToken;
    MockFeeOnTransferERC20 internal _payoutToken;
    MockHook internal _hook;
    Veecode internal _derivativeReference;
    bytes internal _derivativeParams;
    bool internal _wrapDerivative;

    Auctioneer.Routing internal _routingParams;

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        _auctionHouse = new MockAuctionHouse(_PROTOCOL, _PERMIT2_ADDRESS);
        _mockDerivativeModule = new MockDerivativeModule(address(_auctionHouse));

        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);
        _quoteToken.setTransferFee(0);

        _payoutToken = new MockFeeOnTransferERC20("Payout Token", "PAYOUT", 18);
        _payoutToken.setTransferFee(0);

        _derivativeReference = toVeecode(bytes7(""));
        _derivativeParams = bytes("");
        _wrapDerivative = false;

        _routingParams = Auctioneer.Routing({
            auctionReference: wrapVeecode(toKeycode("MOCK"), 1),
            seller: _SELLER,
            baseToken: _payoutToken,
            quoteToken: _quoteToken,
            hooks: _hook,
            allowlist: IAllowlist(address(0)),
            derivativeReference: _derivativeReference,
            derivativeParams: _derivativeParams,
            wrapDerivative: _wrapDerivative,
            funding: 0
        });
    }

    modifier givenSellerHasBalance(uint256 amount_) {
        _payoutToken.mint(_SELLER, amount_);
        _;
    }

    modifier givenSellerHasApprovedRouter() {
        vm.prank(_SELLER);
        _payoutToken.approve(address(_auctionHouse), type(uint256).max);
        _;
    }

    modifier givenTokenTakesFeeOnTransfer() {
        _payoutToken.setTransferFee(1000);
        _;
    }

    // ========== Hooks flow ========== //

    // [X] given the auction has hooks defined
    //  [X] when the mid _hook reverts
    //   [X] it reverts
    //  [X] when the mid _hook does not revert
    //   [X] given the invariant is violated
    //    [X] it reverts
    //   [X] given the invariant is not violated
    //    [X] it succeeds

    modifier givenAuctionHasHook() {
        _hook = new MockHook(address(_quoteToken), address(_payoutToken));
        _routingParams.hooks = _hook;

        // Set the addresses to track
        address[] memory addresses = new address[](5);
        addresses[0] = _USER;
        addresses[1] = _SELLER;
        addresses[2] = address(_auctionHouse);
        addresses[3] = address(_hook);
        addresses[4] = address(_mockDerivativeModule);

        _hook.setBalanceAddresses(addresses);
        _;
    }

    modifier givenMidHookReverts() {
        _hook.setMidHookReverts(true);
        _;
    }

    modifier whenMidHookBreaksInvariant() {
        _hook.setMidHookMultiplier(9000);
        _;
    }

    modifier givenHookHasBalance(uint256 amount_) {
        _payoutToken.mint(address(_hook), amount_);
        _;
    }

    modifier givenHookHasApprovedRouter() {
        vm.prank(address(_hook));
        _payoutToken.approve(address(_auctionHouse), type(uint256).max);
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
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_givenAuctionHasHook_whenMidHookBreaksInvariant_reverts()
        public
        givenAuctionHasHook
        givenHookHasBalance(_payoutAmount)
        givenHookHasApprovedRouter
        whenMidHookBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_givenAuctionHasHook_feeOnTransfer_reverts()
        public
        givenAuctionHasHook
        givenHookHasBalance(_payoutAmount)
        givenHookHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_givenAuctionHasHook()
        public
        givenAuctionHasHook
        givenHookHasBalance(_payoutAmount)
        givenHookHasApprovedRouter
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);

        // Expect the _hook to be called prior to any transfer of the payout token
        assertEq(_hook.midHookCalled(), true);
        assertEq(
            _hook.midHookBalances(_payoutToken, _SELLER), 0, "mid-_hook: seller balance mismatch"
        );
        assertEq(_hook.midHookBalances(_payoutToken, _USER), 0, "mid-_hook: user balance mismatch");
        assertEq(
            _hook.midHookBalances(_payoutToken, address(_auctionHouse)),
            0,
            "mid-_hook: _auctionHouse balance mismatch"
        );
        assertEq(
            _hook.midHookBalances(_payoutToken, address(_hook)),
            _payoutAmount,
            "mid-_hook: _hook balance mismatch"
        );
        assertEq(
            _hook.midHookBalances(_payoutToken, address(_mockDerivativeModule)),
            0,
            "mid-_hook: derivativeModule balance mismatch"
        );

        // Expect the other hooks not to be called
        assertEq(_hook.preHookCalled(), false);
        assertEq(_hook.postHookCalled(), false);

        // Expect payout token balance to be transferred to the _auctionHouse
        assertEq(_payoutToken.balanceOf(_SELLER), 0, "seller balance mismatch");
        assertEq(_payoutToken.balanceOf(_USER), 0, "user balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)),
            _payoutAmount,
            "_auctionHouse balance mismatch"
        );
        assertEq(_payoutToken.balanceOf(address(_hook)), 0, "_hook balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_mockDerivativeModule)),
            0,
            "derivativeModule balance mismatch"
        );
    }

    // ========== Non-hooks flow ========== //

    // [X] given the auction does not have hooks defined
    //  [X] given the seller has insufficient balance of the payout token
    //   [X] it reverts
    //  [X] given the seller has not approved the _auctionHouse to transfer the payout token
    //   [X] it reverts
    //  [X] given transferring the payout token would result in a lesser amount being received
    //   [X] it reverts
    //  [X] it succeeds

    function test_insufficientBalance_reverts() public {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_insufficientAllowance_reverts() public givenSellerHasBalance(_payoutAmount) {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_feeOnTransfer_reverts()
        public
        givenSellerHasBalance(_payoutAmount)
        givenSellerHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(_payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_success()
        public
        givenSellerHasBalance(_payoutAmount)
        givenSellerHasApprovedRouter
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);

        // Expect payout token balance to be transferred to the _auctionHouse
        assertEq(_payoutToken.balanceOf(_SELLER), 0);
        assertEq(_payoutToken.balanceOf(_USER), 0);
        assertEq(_payoutToken.balanceOf(address(_auctionHouse)), _payoutAmount);
        assertEq(_payoutToken.balanceOf(address(_hook)), 0);
        assertEq(_payoutToken.balanceOf(address(_mockDerivativeModule)), 0);
    }

    // ========== Derivative flow ========== //

    // [X] given the auction has a derivative defined
    //  [X] given the auction has hooks defined
    //   [X] given the _hook breaks the invariant
    //    [X] it reverts
    //   [X] it succeeds - base token is transferred to the auction house, mid _hook is called before transfer
    //  [X] given the auction does not have hooks defined
    //   [X] given the seller has insufficient balance of the payout token
    //    [X] it reverts
    //   [X] given the seller has not approved the _auctionHouse to transfer the payout token
    //    [X] it reverts
    //   [X] given transferring the payout token would result in a lesser amount being received
    //    [X] it reverts
    //   [X] it succeeds - base token is transferred to the auction house

    modifier givenAuctionHasDerivative() {
        // Install the derivative module
        _auctionHouse.installModule(_mockDerivativeModule);

        // Update parameters
        _derivativeReference = _mockDerivativeModule.VEECODE();
        _routingParams.derivativeReference = _derivativeReference;
        _;
    }

    function test_derivative_hasHook_whenHookBreaksInvariant_reverts()
        public
        givenAuctionHasDerivative
        givenAuctionHasHook
        givenHookHasBalance(_payoutAmount)
        givenHookHasApprovedRouter
        whenMidHookBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_derivative_hasHook_success()
        public
        givenAuctionHasDerivative
        givenAuctionHasHook
        givenHookHasBalance(_payoutAmount)
        givenHookHasApprovedRouter
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);

        // Expect payout token balance to be transferred to the derivative module
        assertEq(_payoutToken.balanceOf(_SELLER), 0, "payout token: seller balance mismatch");
        assertEq(_payoutToken.balanceOf(_USER), 0, "payout token: user balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)),
            _payoutAmount,
            "payout token: _auctionHouse balance mismatch"
        );
        assertEq(_payoutToken.balanceOf(address(_hook)), 0, "payout token: _hook balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_mockDerivativeModule)),
            0,
            "payout token: derivativeModule balance mismatch"
        );

        // Expect the _hook to be called prior to any transfer of the payout token
        assertEq(_hook.midHookCalled(), true);
        assertEq(
            _hook.midHookBalances(_payoutToken, _SELLER), 0, "mid-_hook: seller balance mismatch"
        );
        assertEq(_hook.midHookBalances(_payoutToken, _USER), 0, "mid-_hook: user balance mismatch");
        assertEq(
            _hook.midHookBalances(_payoutToken, address(_auctionHouse)),
            0,
            "mid-_hook: _auctionHouse balance mismatch"
        );
        assertEq(
            _hook.midHookBalances(_payoutToken, address(_hook)),
            _payoutAmount,
            "mid-_hook: _hook balance mismatch"
        );
        assertEq(
            _hook.midHookBalances(_payoutToken, address(_mockDerivativeModule)),
            0,
            "mid-_hook: derivativeModule balance mismatch"
        );

        // Expect the other hooks not to be called
        assertEq(_hook.preHookCalled(), false);
        assertEq(_hook.postHookCalled(), false);
    }

    function test_derivative_insufficientBalance_reverts() public givenAuctionHasDerivative {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_derivative_insufficientAllowance_reverts()
        public
        givenAuctionHasDerivative
        givenSellerHasBalance(_payoutAmount)
    {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_derivative_feeOnTransfer_reverts()
        public
        givenAuctionHasDerivative
        givenSellerHasBalance(_payoutAmount)
        givenSellerHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(_payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);
    }

    function test_derivative_success()
        public
        givenAuctionHasDerivative
        givenSellerHasBalance(_payoutAmount)
        givenSellerHasApprovedRouter
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);

        // Expect payout token balance to be transferred to the auction house
        assertEq(_payoutToken.balanceOf(_SELLER), 0, "payout token: seller balance mismatch");
        assertEq(_payoutToken.balanceOf(_USER), 0, "payout token: user balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)),
            _payoutAmount,
            "payout token: _auctionHouse balance mismatch"
        );
        assertEq(_payoutToken.balanceOf(address(_hook)), 0, "payout token: _hook balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_mockDerivativeModule)),
            0,
            "payout token: derivativeModule balance mismatch"
        );
    }

    // ========== Prefunding flow ========== //

    // [X] given the auction is pre-funded
    //  [X] it does not transfer the base token to the auction house

    modifier givenAuctionIsPrefunded(uint256 amount_) {
        _routingParams.funding = amount_;
        _;
    }

    modifier givenAuctionHouseHasPayoutTokenBalance(uint256 amount_) {
        _payoutToken.mint(address(_auctionHouse), amount_);
        _;
    }

    function test_prefunded()
        public
        givenAuctionIsPrefunded(_payoutAmount)
        givenSellerHasBalance(_payoutAmount)
        givenSellerHasApprovedRouter
    {
        // Assert previous balance
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)),
            0,
            "payout token: _auctionHouse balance mismatch"
        );

        // Call
        vm.prank(_USER);
        _auctionHouse.collectPayout(_lotId, _paymentAmount, _payoutAmount, _routingParams);

        // Check balances
        assertEq(_payoutToken.balanceOf(_SELLER), 0, "payout token: seller balance mismatch");
        assertEq(_payoutToken.balanceOf(_USER), 0, "payout token: user balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)),
            _payoutAmount,
            "payout token: _auctionHouse balance mismatch"
        );
        assertEq(_payoutToken.balanceOf(address(_hook)), 0, "payout token: _hook balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_mockDerivativeModule)),
            0,
            "payout token: derivativeModule balance mismatch"
        );
    }
}
