// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineCappedAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/CappedAllowlist/BaselineCappedAllowlistTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BALwithCappedAllowlist} from
    "src/callbacks/liquidity/BaselineV2/BALwithCappedAllowlist.sol";

contract BaselineCappedAllowlistOnCreateTest is BaselineCappedAllowlistTest {
    /// @dev This doesn't need to be valid at the moment
    bytes32 internal constant _MERKLE_ROOT =
        0x1234567890123456789012345678901234567890123456789012345678901234;

    // ========== TESTS ========== //

    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] when the buyer limit is 0
    //  [X] it reverts
    // [X] it decodes and stores the merkle root

    function test_allowlistParamsIncorrect_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
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

    function test_buyerLimitZero_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT, uint256(0))
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
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT, _BUYER_LIMIT)
    {
        // Call the callback
        _onCreate();

        // Check the merkle root is stored
        assertEq(BALwithCappedAllowlist(address(_dtl)).merkleRoot(), _MERKLE_ROOT, "merkle root");

        // Check the buyer limit is stored
        assertEq(BALwithCappedAllowlist(address(_dtl)).buyerLimit(), _BUYER_LIMIT, "buyer limit");
    }
}
