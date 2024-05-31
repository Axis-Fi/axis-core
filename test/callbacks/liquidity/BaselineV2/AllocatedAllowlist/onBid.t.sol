// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAllocatedAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/AllocatedAllowlist/BaselineAllocatedAllowlistTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BALwithAllocatedAllowlist} from
    "src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";

contract BaselineAllocatedAllowlistOnBidTest is BaselineAllocatedAllowlistTest {
    // Use the @openzeppelin/merkle-tree package or the scripts in axis-utils to generate the merkle tree

    // Values:
    // 0x0000000000000000000000000000000000000004, 5e18
    // 0x0000000000000000000000000000000000000020, 0
    bytes32 internal constant _MERKLE_ROOT =
        0x0fdc3942d9af344db31ff2e80c06bc4e558dc967ca5b4d421d741870f5ea40df;
    bytes32 internal constant _BUYER_MERKLE_PROOF =
        0x2eac7b0cadd960cd4457012a5e232aa3532d9365ba6df63c1b5a9c7846f77760;
    bytes32 internal constant _NOT_SELLER_MERKLE_PROOF =
        0xe0a73973cd60d8cbabb978d1f3c983065148b388619b9176d3d30e47c16d4fd5;

    bytes32[] internal _proof;
    uint256 internal _allocatedAmount;

    uint64 internal constant _BID_ID = 1;

    // ========== MODIFIER ========== //

    modifier givenMerkleProof(bytes32 merkleProof_) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = merkleProof_;

        _proof = proof;
        _;
    }

    modifier givenMerkleAllocatedAmount(uint256 allocatedAmount_) {
        _allocatedAmount = allocatedAmount_;
        _;
    }

    function _onBid(uint256 bidAmount_) internal {
        // Call the callback
        vm.prank(address(_auctionHouse));
        _dtl.onBid(_lotId, _BID_ID, _BUYER, bidAmount_, abi.encode(_proof, _allocatedAmount));
    }

    // ========== TESTS ========== //

    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] when the merkle proof is invalid
    //  [X] it reverts
    // [X] when the buyer is not in the merkle tree
    //  [X] it reverts
    // [X] when the buyer has already spent their limit
    //  [X] it reverts
    // [X] when the buyer has a 0 limit
    //  [X] it reverts
    // [X] when the buyer has not made a bid
    //  [X] when the bid amount is over the buyer's limit
    //   [X] it reverts
    //  [X] it updates the spent amount with the bid amount
    // [X] when the bid amount is over the remaining limit
    //  [X] it reverts
    // [X] it updates the spent amount with the bid amount

    function test_parametersInvalid_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
    {
        // Expect revert
        vm.expectRevert();

        // Call the callback with an invalid parameter format
        vm.prank(address(_auctionHouse));
        _dtl.onBid(_lotId, _BID_ID, _BUYER, 5e18, abi.encode(uint256(20), bytes("something")));
    }

    function test_merkleProofInvalid_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_NOT_SELLER_MERKLE_PROOF)
        givenMerkleAllocatedAmount(5e18) // Amount is different to what is in the merkle tree
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback with an invalid merkle proof
        _onBid(5e18);
    }

    function test_buyerNotInMerkleTree_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_BUYER_MERKLE_PROOF)
        givenMerkleAllocatedAmount(5e18)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        vm.prank(address(_auctionHouse));
        _dtl.onBid(_lotId, _BID_ID, address(0x55), 5e18, abi.encode(_proof, _allocatedAmount));
    }

    function test_buyerLimitSpent_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_BUYER_MERKLE_PROOF)
        givenMerkleAllocatedAmount(5e18)
    {
        // Spend the allocation
        _onBid(5e18);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BALwithAllocatedAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        // Call the callback again
        _onBid(1e18);
    }

    function test_buyerZeroLimit_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_NOT_SELLER_MERKLE_PROOF)
        givenMerkleAllocatedAmount(0)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BALwithAllocatedAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        // Call the callback
        vm.prank(address(_auctionHouse));
        _dtl.onBid(_lotId, _BID_ID, _NOT_SELLER, 5e18, abi.encode(_proof, _allocatedAmount));
    }

    function test_noBids_aboveLimit_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_BUYER_MERKLE_PROOF)
        givenMerkleAllocatedAmount(5e18)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BALwithAllocatedAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        // Call the callback
        _onBid(6e18);
    }

    function test_noBids_belowLimit()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_BUYER_MERKLE_PROOF)
        givenMerkleAllocatedAmount(5e18)
    {
        // Call the callback
        _onBid(4e18);

        // Check the buyer spent amount
        assertEq(BALwithAllocatedAllowlist(address(_dtl)).buyerSpent(_BUYER), 4e18, "buyer spent");
    }

    function test_remainingLimit_aboveLimit_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_BUYER_MERKLE_PROOF)
        givenMerkleAllocatedAmount(5e18)
    {
        // Spend the allocation
        _onBid(4e18);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BALwithAllocatedAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        // Call the callback again
        _onBid(2e18);
    }

    function test_remainingLimit_belowLimit()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_BUYER_MERKLE_PROOF)
        givenMerkleAllocatedAmount(5e18)
    {
        // Spend the allocation
        _onBid(4e18);

        // Call the callback
        _onBid(1e18);

        // Check the buyer spent amount
        assertEq(BALwithAllocatedAllowlist(address(_dtl)).buyerSpent(_BUYER), 5e18, "buyer spent");
    }
}
