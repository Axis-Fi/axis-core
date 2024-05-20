// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProofLib} from "lib/solady/src/utils/MerkleProofLib.sol";

import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

contract BALwithAllowlist is BaselineAxisLaunch {
    // ========== STATE VARIABLES ========== //

    bytes32 public merkleRoot;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: true
    // onBid: true
    // onSettle: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11111111 = 0xFF

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address baselineKernel_,
        address reserve_
    ) BaselineAxisLaunch(auctionHouse_, permissions_, baselineKernel_, reserve_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    function __onCreate(
        uint96,
        address,
        address,
        address,
        uint256,
        bool,
        bytes memory allowlistData_
    ) internal virtual override {
        // Decode the merkle root from the callback data
        (bytes32 merkleRoot_) = abi.decode(allowlistData_, (bytes32));

        // Set the merkle root and buyer limit
        merkleRoot = merkleRoot_;
    }

    function _onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Validate that the buyer is allowed to participate
        _canParticipate(buyer_, callbackData_);

        // Call any additional implementation-specific logic
        __onBid(lotId_, bidId_, buyer_, amount_, callbackData_);
    }

    function __onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual {}

    // ========== INTERNAL FUNCTIONS ========== //

    function _canParticipate(address buyer_, bytes calldata callbackData_) internal view {
        // Decode the merkle proof from the callback data
        bytes32[] memory proof = abi.decode(callbackData_, (bytes32[]));

        // Get the leaf for the buyer
        bytes32 leaf = keccak256(abi.encodePacked(buyer_));

        // Validate the merkle proof
        if (!MerkleProofLib.verify(proof, merkleRoot, leaf)) {
            revert Callback_NotAuthorized();
        }
    }
}
