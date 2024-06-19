// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

contract BaselineOnCurateTest is BaselineAxisLaunchTest {
    // ============ Modifiers ============ //

    function _performCallback(uint256 curatorFee_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, curatorFee_, true, abi.encode(""));
    }

    // ============ Assertions ============ //

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] when the caller is not the auction house
    //  [X] it reverts
    // [X] when the curator fee is non-zero
    //  [X] it reverts
    // [X] it does nothing

    function test_lotNotRegistered_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        _performCallback(0);
    }

    function test_notAuctionHouse_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Perform callback
        _dtl.onCurate(_lotId, 0, true, abi.encode(""));
    }

    function test_curatorFeeNonZero_reverts(uint256 curatorFee_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
    {
        uint256 curatorFee = bound(curatorFee_, 1, type(uint256).max);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        // Perform callback
        _performCallback(curatorFee);
    }

    function test_curatorFeeZero()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
    {
        // Perform callback
        _performCallback(0);
    }
}
