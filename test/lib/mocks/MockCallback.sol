// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BaseCallback} from "src/lib/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

contract MockCallback is BaseCallback {
    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_
    ) BaseCallback(auctionHouse_, permissions_) {}

    bool public onCreateReverts;
    bool public onCancelReverts;
    bool public onCurateReverts;
    bool public onPurchaseReverts;
    bool public onBidReverts;
    bool public onSettleReverts;

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
    mapping(uint96 => bool) public lotSettled;
    mapping(uint96 => address[]) public buyers;
    mapping(uint96 => mapping(uint64 => address)) public bidder;

    function _onCreate(
        uint96 lotId_,
        address,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata
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
            ERC20(baseToken_).transfer(address(AUCTION_HOUSE), capacity_);
        }
    }

    function _onCancel(uint96 lotId_, uint256, bool, bytes calldata) internal virtual override {
        if (onCancelReverts) {
            revert("revert");
        }

        lotCancelled[lotId_] = true;
    }

    function _onCurate(
        uint96 lotId_,
        uint256 curatorFee_,
        bool prefund_,
        bytes calldata
    ) internal virtual override {
        if (onCurateReverts) {
            revert("revert");
        }

        lotCurated[lotId_] = true;

        if (prefund_) {
            if (onCurateMultiplier > 0) {
                curatorFee_ = uint96(uint256(curatorFee_) * onCurateMultiplier / 1e5);
            }

            // Transfer the base tokens to the auction house
            ERC20(lotTokens[lotId_].baseToken).transfer(address(AUCTION_HOUSE), curatorFee_);
        }
    }

    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256,
        uint256 payout_,
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

        lotPurchased[lotId_] = true;
        buyers[lotId_].push(buyer_);

        if (prefunded_) {
            // Do nothing, as tokens have already been transferred
        } else {
            if (onPurchaseMultiplier > 0) {
                payout_ = uint96(uint256(payout_) * onPurchaseMultiplier / 1e5);
            }

            // Transfer the base tokens to the auction house
            ERC20(lotTokens[lotId_].baseToken).transfer(address(AUCTION_HOUSE), payout_);
        }
    }

    function _onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256,
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
        bidder[lotId_][bidId_] = buyer_;
    }

    function _onSettle(uint96 lotId_, uint256, uint256, bytes calldata) internal virtual override {
        if (onSettleReverts) {
            revert("revert");
        }

        lotSettled[lotId_] = true;
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

    function setOnSettleReverts(bool reverts_) external {
        onSettleReverts = reverts_;
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
