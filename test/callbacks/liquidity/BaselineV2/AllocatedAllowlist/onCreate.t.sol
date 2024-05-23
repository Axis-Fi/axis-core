// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAllocatedAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/AllocatedAllowlist/BaselineAllocatedAllowlistTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BALwithAllocatedAllowlist} from
    "src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";

contract BaselineAllocatedAllowlistOnCreateTest is BaselineAllocatedAllowlistTest {
    /// @dev This doesn't need to be valid at the moment
    bytes32 internal constant _MERKLE_ROOT =
        0x1234567890123456789012345678901234567890123456789012345678901234;

    // ========== TESTS ========== //

    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] it decodes and stores the merkle root

    function test_allowlistParamsIncorrect() public givenCallbackIsCreated givenAuctionIsCreated {
        // Set the allowlist parameters to be an incorrect format
        _createData.allowlistParams = abi.encode(uint256(20), bytes32("hello"));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the callback
        _onCreate();
    }

    function test_success()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
    {
        // Call the callback
        _onCreate();

        // Check the merkle root is stored
        assertEq(BALwithAllocatedAllowlist(address(_dtl)).merkleRoot(), _MERKLE_ROOT, "merkle root");
    }
}
