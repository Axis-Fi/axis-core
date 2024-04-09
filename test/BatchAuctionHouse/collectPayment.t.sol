/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Transfer} from "src/lib/Transfer.sol";

import {MockAuctionHouse} from "test/AuctionHouse/MockAuctionHouse.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {Permit2Clone} from "test/lib/permit2/Permit2Clone.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

contract CollectPaymentTest is Test, Permit2User {
    MockAuctionHouse internal _auctionHouse;

    address internal constant _PROTOCOL = address(0x1);

    uint256 internal _userKey;
    address internal _user;

    // Function parameters
    uint96 internal _lotId = 1;
    uint256 internal _amount = 10e18;
    MockFeeOnTransferERC20 internal _quoteToken;
    uint48 internal _approvalDeadline = 0;
    uint256 internal _approvalNonce = 0;
    bytes internal _approvalSignature = "";

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        _auctionHouse = new MockAuctionHouse(_PROTOCOL, _permit2Address);

        _quoteToken = new MockFeeOnTransferERC20("QUOTE", "QT", 18);
        _quoteToken.setTransferFee(0);

        _userKey = _getRandomUint256();
        _user = vm.addr(_userKey);
    }

    modifier givenUserHasBalance(uint256 amount_) {
        _quoteToken.mint(_user, amount_);
        _;
    }

    modifier givenUserHasApprovedRouter() {
        // As _user, grant approval to transfer quote tokens to the _auctionHouse
        vm.prank(_user);
        _quoteToken.approve(address(_auctionHouse), _amount);
        _;
    }

    modifier givenTokenTakesFeeOnTransfer() {
        // Configure the token to take a 1% fee
        _quoteToken.setTransferFee(100);
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
    //   [X] given the received _amount is not equal to the transferred _amount
    //    [X] it reverts
    //   [X] given the received _amount is the same as the transferred _amount
    //    [X] quote tokens are transferred from the caller to the seller

    modifier givenPermit2Approved() {
        // Approve the Permit2 contract to spend the quote token
        vm.prank(_user);
        _quoteToken.approve(_permit2Address, type(uint256).max);
        _;
    }

    modifier whenPermit2ApprovalIsValid() {
        // Assumes approval has been given

        _approvalNonce = _getRandomUint256();
        _approvalDeadline = uint48(block.timestamp + 1 days);
        _approvalSignature = _signPermit(
            address(_quoteToken),
            _amount,
            _approvalNonce,
            _approvalDeadline,
            address(_auctionHouse),
            _userKey
        );
        _;
    }

    modifier whenPermit2ApprovalNonceIsUsed() {
        // Assumes that whenPermit2ApprovalIsValid precedes this modifier
        require(_approvalNonce != 0, "approval nonce is 0");

        // Mint tokens
        _quoteToken.mint(_user, _amount);

        // Consume the nonce
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
        _;
    }

    modifier whenPermit2ApprovalIsOtherSigner() {
        // Sign as another user
        uint256 anotherUserKey = _getRandomUint256();

        _approvalNonce = _getRandomUint256();
        _approvalDeadline = uint48(block.timestamp + 1 days);
        _approvalSignature = _signPermit(
            address(_quoteToken),
            _amount,
            _approvalNonce,
            _approvalDeadline,
            address(_auctionHouse),
            anotherUserKey
        );
        _;
    }

    modifier whenPermit2ApprovalIsOtherSpender() {
        _approvalNonce = _getRandomUint256();
        _approvalDeadline = uint48(block.timestamp + 1 days);
        _approvalSignature = _signPermit(
            address(_quoteToken),
            _amount,
            _approvalNonce,
            _approvalDeadline,
            address(_PROTOCOL),
            _userKey
        );
        _;
    }

    modifier whenPermit2ApprovalIsInvalid() {
        _approvalNonce = _getRandomUint256();
        _approvalDeadline = uint48(block.timestamp + 1 days);
        _approvalSignature = "JUNK";
        _;
    }

    modifier whenPermit2ApprovalIsExpired() {
        _approvalNonce = _getRandomUint256();
        _approvalDeadline = uint48(block.timestamp - 1 days);
        _approvalSignature = _signPermit(
            address(_quoteToken),
            _amount,
            _approvalNonce,
            _approvalDeadline,
            address(_auctionHouse),
            _userKey
        );
        _;
    }

    function test_permit2_givenNoTokenApproval_reverts()
        public
        givenUserHasBalance(_amount)
        whenPermit2ApprovalIsValid
    {
        // Expect the error
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_permit2_whenApprovalSignatureIsReused_reverts()
        public
        givenUserHasBalance(_amount)
        givenPermit2Approved
        whenPermit2ApprovalIsValid
        whenPermit2ApprovalNonceIsUsed
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(Permit2Clone.InvalidNonce.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_permit2_whenApprovalSignatureIsInvalid_reverts()
        public
        givenUserHasBalance(_amount)
        givenPermit2Approved
        whenPermit2ApprovalIsInvalid
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(Permit2Clone.InvalidSignatureLength.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_permit2_whenApprovalSignatureIsExpired_reverts()
        public
        givenUserHasBalance(_amount)
        givenPermit2Approved
        whenPermit2ApprovalIsExpired
    {
        // Expect the error
        bytes memory err =
            abi.encodeWithSelector(Permit2Clone.SignatureExpired.selector, _approvalDeadline);
        vm.expectRevert(err);

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_permit2_whenApprovalSignatureBelongsToOtherSigner_reverts()
        public
        givenUserHasBalance(_amount)
        givenPermit2Approved
        whenPermit2ApprovalIsOtherSigner
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(Permit2Clone.InvalidSigner.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_permit2_whenApprovalSignatureBelongsToOtherSpender_reverts()
        public
        givenUserHasBalance(_amount)
        givenPermit2Approved
        whenPermit2ApprovalIsOtherSpender
    {
        // Expect the error
        bytes memory err = abi.encodeWithSelector(Permit2Clone.InvalidSigner.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_permit2_whenUserHasInsufficientBalance_reverts()
        public
        givenPermit2Approved
        whenPermit2ApprovalIsValid
    {
        // Expect the error
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_permit2_givenTokenTakesFeeOnTransfer_reverts()
        public
        givenUserHasBalance(_amount)
        givenTokenTakesFeeOnTransfer
        givenPermit2Approved
        whenPermit2ApprovalIsValid
    {
        // Expect the error
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(_quoteToken));
        vm.expectRevert(err);

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_permit2()
        public
        givenUserHasBalance(_amount)
        givenPermit2Approved
        whenPermit2ApprovalIsValid
    {
        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );

        // Expect the user to have no balance
        assertEq(_quoteToken.balanceOf(_user), 0);

        // Expect the _auctionHouse to have the balance
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), _amount);
    }

    // ============ Transfer flow ============

    // [X] when the Permit2 signature is not provided
    //  [X] given the caller has insufficient balance of the quote token
    //   [X] it reverts
    //  [X] given the caller has sufficient balance of the quote token
    //   [X] given the caller has not approved the auction house to transfer the quote token
    //    [X] it reverts
    //   [X] given the received _amount is not equal to the transferred _amount
    //    [X] it reverts
    //   [X] given the received _amount is the same as the transferred _amount
    //    [X] quote tokens are transferred from the caller to the seller

    function test_transfer_whenUserHasInsufficientBalance_reverts() public {
        // Expect the error
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_transfer_givenNoTokenApproval_reverts() public givenUserHasBalance(_amount) {
        // Expect the error
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_transfer_givenTokenTakesFeeOnTransfer_reverts()
        public
        givenUserHasBalance(_amount)
        givenUserHasApprovedRouter
        givenTokenTakesFeeOnTransfer
    {
        // Expect the error
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(_quoteToken));
        vm.expectRevert(err);

        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );
    }

    function test_transfer() public givenUserHasBalance(_amount) givenUserHasApprovedRouter {
        // Call
        vm.prank(_user);
        _auctionHouse.collectPayment(
            _amount,
            _quoteToken,
            Transfer.Permit2Approval({
                deadline: _approvalDeadline,
                nonce: _approvalNonce,
                signature: _approvalSignature
            })
        );

        // Expect the user to have no balance
        assertEq(_quoteToken.balanceOf(_user), 0);

        // Expect the _auctionHouse to have the balance
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), _amount);
    }
}
