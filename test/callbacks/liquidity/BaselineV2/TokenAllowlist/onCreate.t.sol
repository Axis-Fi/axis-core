// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineTokenAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/TokenAllowlist/BaselineTokenAllowlistTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {
    BALwithTokenAllowlist,
    ITokenBalance
} from "src/callbacks/liquidity/BaselineV2/BALwithTokenAllowlist.sol";

contract BaselineTokenAllowlistOnCreateTest is BaselineTokenAllowlistTest {
    // ========== TESTS ========== //

    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] if the token is not a contract
    //  [X] it reverts
    // [X] if the token balance is not retrievable
    //  [X] it reverts
    // [X] it sets the token address and buyer limit

    function test_allowlistParamsIncorrect_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenTokenIsCreated
        givenAuctionIsCreated
    {
        // Set the allowlist parameters to be an incorrect format
        _createData.allowlistParams = abi.encode(uint256(20), bytes32("hello"), uint256(10));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the callback
        _onCreate();
    }

    function test_tokenNotContract_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_SELLER, _TOKEN_THRESHOLD) // Set the token to be an address that is not a contract
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the callback
        _onCreate();
    }

    function test_tokenBalanceNotRetrievable_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenTokenIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(address(_auctionHouse), _TOKEN_THRESHOLD) // Set the token to be a contract that does not have a balanceOf function
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the callback
        _onCreate();
    }

    function test_success()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenTokenIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(address(_token), _TOKEN_THRESHOLD)
    {
        // Call the callback
        _onCreate();

        // Check the token address and buyer limit are stored
        (ITokenBalance token, uint256 threshold) = BALwithTokenAllowlist(address(_dtl)).tokenCheck();

        assertEq(address(token), address(_token), "token address");
        assertEq(threshold, _TOKEN_THRESHOLD, "token threshold");
    }
}
