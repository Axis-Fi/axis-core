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

contract RouterTest is Test, Permit2User {
    ConcreteRouter internal router;

    address internal constant PROTOCOL = address(0x1);

    uint256 internal userKey;
    address internal USER;

    // Function parameters
    uint256 internal lotId = 1;
    uint256 internal amount = 10e18;
    MockFeeOnTransferERC20 internal quoteToken;
    MockHook internal hook;
    uint48 internal approvalDeadline = 0;
    uint256 internal approvalNonce = 0;
    bytes internal approvalSignature = "";

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        router = new ConcreteRouter(PROTOCOL, _PERMIT2_ADDRESS);

        quoteToken = new MockFeeOnTransferERC20("QUOTE", "QT", 18);
        quoteToken.setTransferFee(0);

        userKey = _getRandomUint256();
        USER = vm.addr(userKey);
    }

    modifier givenUserHasBalance(uint256 amount_) {
        quoteToken.mint(USER, amount_);
        _;
    }

    modifier givenUserHasApprovedRouter() {
        // As USER, grant approval to transfer quote tokens to the router
        vm.prank(USER);
        quoteToken.approve(address(router), amount);
        _;
    }

    modifier givenTokenTakesFeeOnTransfer() {
        // Configure the token to take a 1% fee
        quoteToken.setTransferFee(100);
        _;
    }

    // ============ Permit2 flow ============

    // [X] when the Permit2 signature is provided
    //  [X] when the Permit2 signature is invalid
    //   [X] it reverts
    //  [X] when the Permit2 signature is expired
    //   [X] it reverts
    //  [X] when the Permit2 signature is valid
    //   [X] given the caller has insufficient balance of the quote token
    //    [X] it reverts
    //   [X] given the received amount is not equal to the transferred amount
    //    [X] it reverts
    //   [X] given the received amount is the same as the transferred amount
    //    [X] quote tokens are transferred from the caller to the auction owner

    modifier givenPermit2Approved() {
        // Approve the Permit2 contract to spend the quote token
        vm.prank(USER);
        quoteToken.approve(_PERMIT2_ADDRESS, type(uint256).max);
        _;
    }

    modifier whenPermit2ApprovalIsValid() {
        // Assumes approval has been given

        approvalNonce = _getRandomUint256();
        approvalDeadline = uint48(block.timestamp + 1 days);
        approvalSignature = _signPermit(
            address(quoteToken), amount, approvalNonce, approvalDeadline, address(router), userKey
        );
        _;
    }

    modifier whenPermit2ApprovalNonceIsUsed() {
        // Assumes that whenPermit2ApprovalIsValid precedes this modifier
        require(approvalNonce != 0, "approval nonce is 0");

        // Mint tokens
        quoteToken.mint(USER, amount);

        // Consume the nonce
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
        _;
    }

    modifier whenPermit2ApprovalIsOtherSigner() {
        // Sign as another user
        uint256 anotherUserKey = _getRandomUint256();

        approvalNonce = _getRandomUint256();
        approvalDeadline = uint48(block.timestamp + 1 days);
        approvalSignature = _signPermit(
            address(quoteToken),
            amount,
            approvalNonce,
            approvalDeadline,
            address(router),
            anotherUserKey
        );
        _;
    }

    modifier whenPermit2ApprovalIsOtherSpender() {
        approvalNonce = _getRandomUint256();
        approvalDeadline = uint48(block.timestamp + 1 days);
        approvalSignature = _signPermit(
            address(quoteToken), amount, approvalNonce, approvalDeadline, address(PROTOCOL), userKey
        );
        _;
    }

    modifier whenPermit2ApprovalIsInvalid() {
        approvalNonce = _getRandomUint256();
        approvalDeadline = uint48(block.timestamp + 1 days);
        approvalSignature = "JUNK";
        _;
    }

    modifier whenPermit2ApprovalIsExpired() {
        approvalNonce = _getRandomUint256();
        approvalDeadline = uint48(block.timestamp - 1 days);
        approvalSignature = _signPermit(
            address(quoteToken), amount, approvalNonce, approvalDeadline, address(router), userKey
        );
        _;
    }

    function test_permit2_givenNoTokenApproval_reverts()
        public
        givenUserHasBalance(amount)
        whenPermit2ApprovalIsValid
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(
            Router.InsufficientAllowance.selector, address(quoteToken), _PERMIT2_ADDRESS, amount
        );
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_permit2_whenApprovalSignatureIsReused_reverts()
        public
        givenUserHasBalance(amount)
        givenPermit2Approved
        whenPermit2ApprovalIsValid
        whenPermit2ApprovalNonceIsUsed
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(Permit2Clone.InvalidNonce.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_permit2_whenApprovalSignatureIsInvalid_reverts()
        public
        givenUserHasBalance(amount)
        givenPermit2Approved
        whenPermit2ApprovalIsInvalid
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(Permit2Clone.InvalidSignatureLength.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_permit2_whenApprovalSignatureIsExpired_reverts()
        public
        givenUserHasBalance(amount)
        givenPermit2Approved
        whenPermit2ApprovalIsExpired
    {
        // Expect the error
        bytes memory err =
            abi.encodeWithSelector(Permit2Clone.SignatureExpired.selector, approvalDeadline);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_permit2_whenApprovalSignatureBelongsToOtherSigner_reverts()
        public
        givenUserHasBalance(amount)
        givenPermit2Approved
        whenPermit2ApprovalIsOtherSigner
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(Permit2Clone.InvalidSigner.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_permit2_whenApprovalSignatureBelongsToOtherSpender_reverts()
        public
        givenUserHasBalance(amount)
        givenPermit2Approved
        whenPermit2ApprovalIsOtherSpender
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(Permit2Clone.InvalidSigner.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_permit2_whenUserHasInsufficientBalance_reverts()
        public
        givenPermit2Approved
        whenPermit2ApprovalIsValid
    {
        // Expect the error
        bytes memory err =
            abi.encodeWithSelector(Router.InsufficientBalance.selector, address(quoteToken), amount);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_permit2_givenTokenTakesFeeOnTransfer_reverts()
        public
        givenUserHasBalance(amount)
        givenTokenTakesFeeOnTransfer
        givenPermit2Approved
        whenPermit2ApprovalIsValid
    {
        // Expect the error
        bytes memory err =
            abi.encodeWithSelector(Router.UnsupportedToken.selector, address(quoteToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_permit2()
        public
        givenUserHasBalance(amount)
        givenPermit2Approved
        whenPermit2ApprovalIsValid
    {
        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );

        // Expect the user to have no balance
        assertEq(quoteToken.balanceOf(USER), 0);

        // Expect the router to have the balance
        assertEq(quoteToken.balanceOf(address(router)), amount);
    }

    // ============ Transfer flow ============

    // [X] when the Permit2 signature is not provided
    //  [X] given the caller has insufficient balance of the quote token
    //   [X] it reverts
    //  [X] given the caller has sufficient balance of the quote token
    //   [X] given the caller has not approved the auction house to transfer the quote token
    //    [X] it reverts
    //   [X] given the received amount is not equal to the transferred amount
    //    [X] it reverts
    //   [X] given the received amount is the same as the transferred amount
    //    [X] quote tokens are transferred from the caller to the auction owner

    function test_transfer_whenUserHasInsufficientBalance_reverts() public {
        // Expect the error
        bytes memory err =
            abi.encodeWithSelector(Router.InsufficientBalance.selector, address(quoteToken), amount);
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_transfer_givenNoTokenApproval_reverts() public givenUserHasBalance(amount) {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(
            Router.InsufficientAllowance.selector, address(quoteToken), address(router), amount
        );
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_transfer_givenTokenTakesFeeOnTransfer_reverts()
        public
        givenUserHasBalance(amount)
        givenUserHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect the error
        bytes memory err =
            abi.encodeWithSelector(Router.UnsupportedToken.selector, address(quoteToken));
        vm.expectRevert(err);

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_transfer() public givenUserHasBalance(amount) givenUserHasApprovedRouter {
        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );

        // Expect the user to have no balance
        assertEq(quoteToken.balanceOf(USER), 0);

        // Expect the router to have the balance
        assertEq(quoteToken.balanceOf(address(router)), amount);
    }

    // ============ Hooks flow ============

    // [X] given the auction has hooks defined
    //  [X] when the pre hook reverts
    //   [X] it reverts
    //  [ ] when the pre hook does not revert
    //   [ ] given the invariant is violated
    //    [ ] it reverts
    //   [X] given the invariant is not violated - TODO define invariant
    //    [X] it succeeds

    modifier whenHooksIsSet() {
        hook = new MockHook();
        _;
    }

    modifier whenPreHookReverts() {
        hook.setPreHookReverts(true);
        _;
    }

    modifier whenPreHookBalanceIsRecorded() {
        hook.setPreHookValues(address(quoteToken), USER);
        _;
    }

    function test_preHook_reverts() public whenHooksIsSet whenPreHookReverts {
        // Expect the error
        vm.expectRevert("revert");

        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );
    }

    function test_preHook_withTransfer()
        public
        givenUserHasBalance(amount)
        givenUserHasApprovedRouter
        whenHooksIsSet
        whenPreHookBalanceIsRecorded
    {
        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );

        // Expect the pre hook to have recorded the balance of USER before the transfer
        assertEq(hook.preHookBalance(), amount);
        assertEq(quoteToken.balanceOf(USER), 0);
    }

    function test_preHook_withPermit2()
        public
        givenUserHasBalance(amount)
        givenPermit2Approved
        whenPermit2ApprovalIsValid
        whenHooksIsSet
        whenPreHookBalanceIsRecorded
    {
        // Call
        vm.prank(USER);
        router.collectPayment(
            lotId, amount, quoteToken, hook, approvalDeadline, approvalNonce, approvalSignature
        );

        // Expect the pre hook to have recorded the balance of USER before the transfer
        assertEq(hook.preHookBalance(), amount);
        assertEq(quoteToken.balanceOf(USER), 0);
    }
}
