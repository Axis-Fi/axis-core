// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Owned} from "lib/solmate/src/auth/Owned.sol";

import {ICallback} from "src/interfaces/ICallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

abstract contract BaseCallback is ICallback, Owned {
    // ========== ERRORS ========== //

    error Callback_InvalidParams();
    error Callback_NotAuthorized();
    error Callback_NotImplemented();

    // ========== STATE VARIABLES ========== //

    address public auctionHouse;
    address public seller;
    mapping(uint96 => bool) public lotIdRegistered;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address seller_
    ) Owned(seller_) {
        // Validate the permissions against the deployed address
        Callbacks.validateCallbacksPermissions(this, permissions_);

        // Set the auction house and seller
        auctionHouse = auctionHouse_;
        seller = seller_;
    }

    // ========== MODIFIERS ========== //

    modifier onlyAuctionHouse() {
        if (msg.sender != auctionHouse) revert Callback_NotAuthorized();
        _;
    }

    modifier onlyRegisteredLot(uint96 lotId_) {
        if (!lotIdRegistered[lotId_]) revert Callback_NotAuthorized();
        _;
    }

    // ========== CALLBACK FUNCTIONS ========== //

    function onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint96 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse returns (bytes4) {
        // Validate the seller
        if (seller_ != seller) revert Callback_NotAuthorized();

        // Validate the lot registration
        if (lotIdRegistered[lotId_]) revert Callback_InvalidParams();

        // Set the lot ID as registered
        lotIdRegistered[lotId_] = true;

        // Call implementation specific logic
        // If prefund_ is true, then the AuctionHouse will expect the capacity_ of base tokens to be sent back
        _onCreate(lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, callbackData_);

        return this.onCreate.selector;
    }

    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint96 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual;

    function onCancel(
        uint96 lotId_,
        uint96 refund_,
        bool prefunded_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        // If prefunded_ is true, then the refund_ will be sent prior to the call
        _onCancel(lotId_, refund_, prefunded_, callbackData_);

        return this.onCancel.selector;
    }

    function _onCancel(
        uint96 lotId_,
        uint96 refund_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual;

    function onCurate(
        uint96 lotId_,
        uint96 curatorFee_,
        bool prefund_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        // If prefund_ is true, then the AuctionHouse will expect the curatorFee_ of base tokens to be sent back
        _onCurate(lotId_, curatorFee_, prefund_, callbackData_);

        return this.onCurate.selector;
    }

    function _onCurate(
        uint96 lotId_,
        uint96 curatorFee_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual;

    function onPurchase(
        uint96 lotId_,
        address buyer_,
        uint96 amount_,
        uint96 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        // If prefunded, then the payout of base tokens will be sent back
        _onPurchase(lotId_, buyer_, amount_, payout_, prefunded_, callbackData_);

        return this.onPurchase.selector;
    }

    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint96 amount_,
        uint96 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual;

    function onBid(
        uint96 lotId_,
        uint64 bidId,
        address buyer_,
        uint96 amount_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        _onBid(lotId_, bidId, buyer_, amount_, callbackData_);

        return this.onBid.selector;
    }

    function _onBid(
        uint96 lotId_,
        uint64 bidId,
        address buyer_,
        uint96 amount_,
        bytes calldata callbackData_
    ) internal virtual;

    function onClaimProceeds(
        uint96 lotId_,
        uint96 proceeds_,
        uint96 refund_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        _onClaimProceeds(lotId_, proceeds_, refund_, callbackData_);

        return this.onClaimProceeds.selector;
    }

    function _onClaimProceeds(
        uint96 lotId_,
        uint96 proceeds_,
        uint96 refund_,
        bytes calldata callbackData_
    ) internal virtual;

    // ========== ADMIN FUNCTIONS ========= //

    function setSeller(address seller_) external onlyOwner {
        seller = seller_;
    }
}
