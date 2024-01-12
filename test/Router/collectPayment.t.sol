/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {MockHook} from "test/modules/Auction/MockHook.sol";
import {ConcreteRouter} from "test/Router/ConcreteRouter.sol";
import {MockFeeOnTransferERC20} from "test/Router/MockFeeOnTransferERC20.sol";

import {IHooks} from "src/interfaces/IHooks.sol";

contract RouterTest is Test {
    ConcreteRouter internal router;

    address internal constant PROTOCOL = address(0x1);
    address internal constant USER = address(0x2);

    // Function parameters
    uint256 internal lotId = 1;
    uint256 internal amount = 10e18;
    MockFeeOnTransferERC20 internal quoteToken;
    MockHook internal hook;
    uint48 internal approvalDeadline = 0;
    uint256 internal approvalNonce = 0;
    bytes internal approvalSignature = "";

    function setUp() public {
        router = new ConcreteRouter(PROTOCOL);

        quoteToken = new MockFeeOnTransferERC20("QUOTE", "QT", 18);
        quoteToken.setTransferFee(0);
    }

    modifier givenUserHasBalance(uint256 amount_) {
        quoteToken.mint(USER, amount_);
        _;
    }

    modifier whenPermit2ApprovalIsValid() {
        // TODO
        _;
    }

    modifier whenPermit2ApprovalIsInvalid() {
        // TODO
        _;
    }

    modifier whenPermit2ApprovalIsExpired() {
        // TODO
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

    // [ ] when the Permit2 signature is provided
    //  [ ] when the Permit2 signature is invalid
    //   [ ] it reverts
    //  [ ] when the Permit2 signature is expired
    //   [ ] it reverts
    //  [ ] when the Permit2 signature is valid
    //   [ ] given the caller has insufficient balance of the quote token
    //    [ ] it reverts
    //   [ ] given the received amount is not equal to the transferred amount
    //    [ ] it reverts
    //   [ ] given the received amount is the same as the transferred amount
    //    [ ] quote tokens are transferred from the caller to the auction owner
    // [ ] when the Permit2 signature is not provided
    //  [ ] given the caller has insufficient balance of the quote token
    //   [ ] it reverts
    //  [ ] given the caller has sufficient balance of the quote token
    //   [ ] given the caller has not approved the auction house to transfer the quote token
    //    [ ] it reverts
    //   [ ] given the received amount is not equal to the transferred amount
    //    [ ] it reverts
    //   [ ] given the received amount is the same as the transferred amount
    //    [ ] quote tokens are transferred from the caller to the auction owner

    // [ ] given the auction has hooks defined
    //  [ ] when the pre hook reverts
    //   [ ] it reverts
    //  [ ] when the pre hook does not revert
    //   [ ] given the invariant is violated
    //    [ ] it reverts
    //   [ ] given the invariant is not violated - TODO define invariant
    //    [ ] it succeeds

    modifier whenHooksIsSet() {
        hook = new MockHook();
        _;
    }

    modifier whenPreHookReverts() {
        hook.setPreHookReverts(true);
        _;
    }
}
