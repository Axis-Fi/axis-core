// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @notice Generic interface for tokens that implement a balanceOf function (includes ERC-20 and ERC-721)
interface ITokenBalance {
    /// @notice Get the user's token balance
    function balanceOf(address user_) external view returns (uint256);
}

/// @title  TokenAllowlist Callback Contract
/// @notice Allowlist contract that checks if a user's balance of a token is above a threshold
/// @dev    This shouldn't be used with liquid, transferable ERC-20s because it can easily be bypassed via flash loans or other swap mechanisms
/// @dev    The intent is to use this with non-transferable tokens (e.g. vote escrow) or illiquid tokens that are not as easily manipulated, e.g. community NFTs
contract TokenAllowlist is BaseCallback {
    // ========== ERRORS ========== //

    // ========== STATE VARIABLES ========== //

    struct TokenCheck {
        ITokenBalance token;
        uint96 threshold;
    }

    mapping(uint96 lotId => TokenCheck) public lotChecks;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: false
    // onCurate: false
    // onPurchase: true
    // onBid: true
    // onClaimProceeds: false
    // receiveQuoteTokens: false
    // sendBaseTokens: false
    // Contract prefix should be: 10011000 = 0x98

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address seller_
    ) BaseCallback(auctionHouse_, permissions_, seller_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    function _onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint96,
        bool,
        bytes calldata callbackData_
    ) internal override {
        // Decode the params to get the token contract and balance threshold
        (ITokenBalance token, uint96 threshold) = abi.decode(callbackData_, (ITokenBalance, uint96));

        // Token must be a contract
        if (address(token).code.length == 0) revert Callback_InvalidParams();

        // Try to get balance for token, revert if it fails
        try token.balanceOf(address(this)) returns (uint256) {}
        catch {
            revert Callback_InvalidParams();
        }

        // Set the lot check
        lotChecks[lotId_] = TokenCheck(token, threshold);
    }

    function _onCancel(uint96, uint96, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onCurate(uint96, uint96, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint96,
        uint96,
        bool,
        bytes calldata
    ) internal view override {
        _canParticipate(lotId_, buyer_);
    }

    function _onBid(
        uint96 lotId_,
        uint64,
        address buyer_,
        uint96,
        bytes calldata
    ) internal view override {
        _canParticipate(lotId_, buyer_);
    }

    function _onClaimProceeds(uint96, uint96, uint96, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _canParticipate(uint96 lotId_, address buyer_) internal view {
        // Get the token check
        TokenCheck memory check = lotChecks[lotId_];

        // Check if the buyer's balance is above the threshold
        if (check.token.balanceOf(buyer_) < check.threshold) revert Callback_NotAuthorized();
    }
}
