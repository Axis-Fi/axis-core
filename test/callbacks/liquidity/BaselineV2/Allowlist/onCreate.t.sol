// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/Allowlist/BaselineAllowlistTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BALwithAllowlist} from "src/callbacks/liquidity/BaselineV2/BALwithAllowlist.sol";

contract BaselineAllowlistOnCreateTest is BaselineAllowlistTest {
    /// @dev This doesn't need to be valid at the moment
    bytes32 internal constant _MERKLE_ROOT =
        0x1234567890123456789012345678901234567890123456789012345678901234;

    // ========== TESTS ========== //

    // [X] when the allowlist parameters are in an incorrect format
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

    function test_success()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
    {
        // Call the callback
        _onCreate();

        // Check the merkle root is stored
        assertEq(BALwithAllowlist(address(_dtl)).merkleRoot(), _MERKLE_ROOT, "merkle root");
    }
}
