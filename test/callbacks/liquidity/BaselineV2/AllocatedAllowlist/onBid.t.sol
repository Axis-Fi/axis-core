// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAllocatedAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/AllocatedAllowlist/BaselineAllocatedAllowlistTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BALwithAllocatedAllowlist} from
    "src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";

contract BaselineAllocatedAllowlistOnBidTest is BaselineAllocatedAllowlistTest {
    // Number values need to be converted to hex
    // cast to-uint256 5000000000000000000 = 0x0000000000000000000000000000000000000000000000004563918244f40000
    // Then concatenated with the address
    // cast concat-hex "0x0000000000000000000000000000000000000004" "0x0000000000000000000000000000000000000000000000004563918244f40000"
    // Then hashed with keccak256
    // cast keccak 0x00000000000000000000000000000000000000040000000000000000000000000000000000000000000000004563918244f40000 = 0x48371c09b043f1a28e5b80a2b295dcedc7e596fa1faacf355af6611b4d4eddc3
    // The hashed values can then be entered as leaves here: https://lab.miguelmota.com/merkletreejs/example/

    // Values:
    // 0x0000000000000000000000000000000000000004, 5e18
    // 0x0000000000000000000000000000000000000020, 0
    bytes32 internal constant _MERKLE_ROOT =
        0x31d4f5b0409c3135a0fafee5c3d0d55f60dc000c375a08253792018af634c7f8;
    bytes32 internal constant _BUYER_MERKLE_PROOF =
        0xa74918dea25af42011aa97c6f1afcb94b1677e783fad462fe50b7436df9d5d38;
    bytes32 internal constant _NOT_SELLER_MERKLE_PROOF =
        0x48371c09b043f1a28e5b80a2b295dcedc7e596fa1faacf355af6611b4d4eddc3;
    BALwithAllocatedAllowlist.AllocatedAllowlistBidParams internal _bidParams;

    uint64 internal constant _BID_ID = 1;

    // ========== MODIFIER ========== //

    modifier givenMerkleProof(bytes32 merkleProof_) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = merkleProof_;

        _bidParams.proof = proof;
        _;
    }

    modifier givenMerkleAllocatedAmount(uint256 allocatedAmount_) {
        _bidParams.allocatedAmount = allocatedAmount_;
        _;
    }

    function _onBid(uint256 bidAmount_) internal {
        // Call the callback
        vm.prank(address(_auctionHouse));
        _dtl.onBid(_lotId, _BID_ID, _BUYER, bidAmount_, abi.encode(_bidParams));
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
        _dtl.onBid(_lotId, _BID_ID, address(0x55), 5e18, abi.encode(_bidParams));
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
        _dtl.onBid(_lotId, _BID_ID, _NOT_SELLER, 5e18, abi.encode(_bidParams));
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
