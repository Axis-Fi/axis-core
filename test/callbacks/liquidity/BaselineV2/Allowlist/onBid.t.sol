// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/Allowlist/BaselineAllowlistTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

contract BaselineAllowlistOnBidTest is BaselineAllowlistTest {
    // Use the @openzeppelin/merkle-tree package or the scripts in axis-utils to generate the merkle tree

    // Values:
    // 0x0000000000000000000000000000000000000004
    // 0x0000000000000000000000000000000000000005
    bytes32 internal constant _MERKLE_ROOT =
        0xc92348ba87c65979cc4f264810321a35efa64e795075908af2c507a22d4da472;
    bytes32 internal constant _BUYER_MERKLE_PROOF =
        0x16db2e4b9f8dc120de98f8491964203ba76de27b27b29c2d25f85a325cd37477;
    bytes32 internal constant _NOT_SELLER_MERKLE_PROOF =
        0xc167b0e3c82238f4f2d1a50a8b3a44f96311d77b148c30dc0ef863e1a060dcb6;

    bytes32[] internal _proof;

    uint64 internal constant _BID_ID = 1;

    // ========== MODIFIER ========== //

    modifier givenMerkleProof(bytes32 merkleProof_) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = merkleProof_;

        _proof = proof;
        _;
    }

    function _onBid(uint256 bidAmount_) internal {
        // Call the callback
        vm.prank(address(_auctionHouse));
        _dtl.onBid(_lotId, _BID_ID, _BUYER, bidAmount_, abi.encode(_proof));
    }

    // ========== TESTS ========== //

    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] when the merkle proof is invalid
    //  [X] it reverts
    // [X] when the buyer is not in the merkle tree
    //  [X] it reverts
    // [X] it succeeds

    function test_parametersInvalid_reverts()
        public
        givenBPoolIsCreated
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
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_NOT_SELLER_MERKLE_PROOF)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback with an invalid merkle proof
        _onBid(5e18);
    }

    function test_buyerNotInMerkleTree_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_BUYER_MERKLE_PROOF)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        vm.prank(address(_auctionHouse));
        _dtl.onBid(_lotId, _BID_ID, address(0x55), 5e18, abi.encode(_proof));
    }

    function test_success(uint256 bidAmount_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(_MERKLE_ROOT)
        givenOnCreate
        givenMerkleProof(_BUYER_MERKLE_PROOF)
    {
        // Call the callback
        _onBid(bidAmount_);

        // Does not revert
    }
}
