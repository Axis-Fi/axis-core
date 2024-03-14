// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

contract MockCallback is BaseCallback {
    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address seller_
    ) BaseCallback(auctionHouse_, permissions_, seller_) {}

    bool public onCreateReverts;
    bool public onCancelReverts;
    bool public onCurateReverts;
    bool public onPurchaseReverts;
    bool public onBidReverts;
    bool public onClaimProceedsReverts;

    uint48 public onCreateMultiplier;
    uint48 public onCurateMultiplier;
    uint48 public onPurchaseMultiplier;

    bool public allowlistEnabled;

    mapping(address => mapping(bytes => bool)) public allowedWithProof;

    struct LotTokens {
        address baseToken;
        address quoteToken;
    }

    mapping(uint96 => LotTokens) public lotTokens;
    mapping(uint96 => bool) public lotCreated;
    mapping(uint96 => bool) public lotCancelled;
    mapping(uint96 => bool) public lotCurated;
    mapping(uint96 => bool) public lotPurchased;
    mapping(uint96 => bool) public lotBid;
    mapping(uint96 => bool) public lotClaimedProceeds;

    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint96 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual override {
        if (onCreateReverts) {
            revert("revert");
        }

        lotTokens[lotId_] = LotTokens({baseToken: baseToken_, quoteToken: quoteToken_});
        lotCreated[lotId_] = true;

        if (prefund_) {
            if (onCreateMultiplier > 0) {
                capacity_ = uint96(uint256(capacity_) * onCreateMultiplier / 1e5);
            }

            // Transfer the base tokens to the auction house
            ERC20(baseToken_).transfer(address(auctionHouse), capacity_);
        }
    }

    function _onCancel(
        uint96 lotId_,
        uint96 refund_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual override {
        if (onCancelReverts) {
            revert("revert");
        }

        lotCancelled[lotId_] = true;
    }

    function _onCurate(
        uint96 lotId_,
        uint96 curatorFee_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual override {
        if (onCurateReverts) {
            revert("revert");
        }

        if (prefund_) {
            if (onCurateMultiplier > 0) {
                curatorFee_ = uint96(uint256(curatorFee_) * onCurateMultiplier / 1e5);
            }

            // Transfer the base tokens to the auction house
            ERC20(lotTokens[lotId_].baseToken).transfer(address(auctionHouse), curatorFee_);
        }

        lotCurated[lotId_] = true;
    }

    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint96 amount_,
        uint96 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual override {
        if (onPurchaseReverts) {
            revert("revert");
        }

        // Check if allowed
        if (allowlistEnabled && !allowedWithProof[buyer_][callbackData_]) {
            revert("not allowed");
        }

        if (prefunded_) {
            // Do nothing, as tokens have already been transferred
        } else {
            if (onPurchaseMultiplier > 0) {
                payout_ = uint96(uint256(payout_) * onPurchaseMultiplier / 1e5);
            }

            // Transfer the base tokens to the auction house
            ERC20(lotTokens[lotId_].baseToken).transfer(address(auctionHouse), payout_);
        }

        lotPurchased[lotId_] = true;
    }

    function _onBid(
        uint96 lotId_,
        uint64 bidId,
        address buyer_,
        uint96 amount_,
        bytes calldata callbackData_
    ) internal virtual override {
        if (onBidReverts) {
            revert("revert");
        }

        // Check if allowed
        if (allowlistEnabled && !allowedWithProof[buyer_][callbackData_]) {
            revert("not allowed");
        }

        lotBid[lotId_] = true;
    }

    function _onClaimProceeds(
        uint96 lotId_,
        uint96 proceeds_,
        uint96 refund_,
        bytes calldata callbackData_
    ) internal virtual override {
        if (onClaimProceedsReverts) {
            revert("revert");
        }

        lotClaimedProceeds[lotId_] = true;
    }

    function setOnCreateReverts(bool reverts_) external {
        onCreateReverts = reverts_;
    }

    function setOnCancelReverts(bool reverts_) external {
        onCancelReverts = reverts_;
    }

    function setOnCurateReverts(bool reverts_) external {
        onCurateReverts = reverts_;
    }

    function setOnPurchaseReverts(bool reverts_) external {
        onPurchaseReverts = reverts_;
    }

    function setOnBidReverts(bool reverts_) external {
        onBidReverts = reverts_;
    }

    function setOnClaimProceedsReverts(bool reverts_) external {
        onClaimProceedsReverts = reverts_;
    }

    function setOnCreateMultiplier(uint48 multiplier_) external {
        onCreateMultiplier = multiplier_;
    }

    function setOnCurateMultiplier(uint48 multiplier_) external {
        onCurateMultiplier = multiplier_;
    }

    function setOnPurchaseMultiplier(uint48 multiplier_) external {
        onPurchaseMultiplier = multiplier_;
    }

    function setAllowlistEnabled(bool enabled_) external {
        allowlistEnabled = enabled_;
    }

    function setAllowedWithProof(address account, bytes calldata proof, bool allowed_) external {
        allowedWithProof[account][proof] = allowed_;
    }
}
