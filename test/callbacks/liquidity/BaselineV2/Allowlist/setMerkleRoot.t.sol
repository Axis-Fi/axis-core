// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/Allowlist/BaselineAllowlistTest.sol";

import {BALwithAllowlist} from "src/callbacks/liquidity/BaselineV2/BALwithAllowlist.sol";

contract BaselineAllowlistSetMerkleRootTest is BaselineAllowlistTest {
    /// @dev This doesn't need to be valid at the moment
    bytes32 internal constant _MERKLE_ROOT =
        0x1234567890123456789012345678901234567890123456789012345678901234;
    bytes32 internal constant _NEW_MERKLE_ROOT =
        0x1234567890123456789012345678901234567890123456789012345678901234;

    function _setMerkleRoot() internal {
        vm.prank(_OWNER);
        BALwithAllowlist(address(_dtl)).setMerkleRoot(_NEW_MERKLE_ROOT);
    }

    // ========== TESTS ========== //

    // [X] when the caller is not the owner
    //  [X] it reverts
    // [X] when the auction has not been registered
    //  [X] it reverts
    // [X] when the auction has been completed
    //  [X] it reverts
    // [X] the merkle root is updated and an event is emitted

    function test_notOwner_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
    {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Call the callback
        BALwithAllowlist(address(_dtl)).setMerkleRoot(_NEW_MERKLE_ROOT);
    }

    function test_auctionNotRegistered_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BALwithAllowlist.Callback_InvalidState.selector);
        vm.expectRevert(err);

        // Call the callback
        _setMerkleRoot();
    }

    function test_auctionCompleted_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenAddressHasBaseTokenBalance(_dtlAddress, _REFUND_AMOUNT)
        givenOnSettle
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BALwithAllowlist.Callback_InvalidState.selector);
        vm.expectRevert(err);

        // Call the callback
        _setMerkleRoot();
    }

    function test_success()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
    {
        // Call the callback
        _setMerkleRoot();

        // Check the merkle root is updated
        assertEq(BALwithAllowlist(address(_dtl)).merkleRoot(), _NEW_MERKLE_ROOT, "merkle root");
    }
}
