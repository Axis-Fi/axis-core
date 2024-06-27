// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";

/// @notice Generic interface for tokens that implement a balanceOf function (includes ERC-20 and ERC-721)
interface ITokenBalance {
    /// @notice Get the user's token balance
    function balanceOf(address user_) external view returns (uint256);
}

/// @notice TokenAllowlist version of the Baseline Axis Launch callback.
/// @notice Allowlist contract that checks if a user's balance of a token is above a threshold
/// @dev    This shouldn't be used with liquid, transferable ERC-20s because it can easily be bypassed via flash loans or other swap mechanisms
/// @dev    The intent is to use this with non-transferable tokens (e.g. vote escrow) or illiquid tokens that are not as easily manipulated, e.g. community NFTs
contract BALwithTokenAllowlist is BaselineAxisLaunch {
    // ========== ERRORS ========== //

    // ========== EVENTS ========== //

    // ========== STATE VARIABLES ========== //

    struct TokenCheck {
        ITokenBalance token;
        uint256 threshold;
    }

    /// @notice Stores the token and balance threshold for the lot
    TokenCheck public tokenCheck;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: false
    // onBid: true
    // onSettle: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11101111 = 0xEF

    constructor(
        address auctionHouse_,
        address baselineKernel_,
        address reserve_,
        address owner_
    ) BaselineAxisLaunch(auctionHouse_, baselineKernel_, reserve_, owner_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaselineAxisLaunch
    /// @dev        This function reverts if:
    ///             - `allowlistData_` is not of the correct length
    ///
    /// @param      allowlistData_  abi-encoded data: (ITokenBalance, uint96) representing the token contract and minimum balance
    function __onCreate(
        uint96,
        address,
        address,
        address,
        uint256,
        bool,
        bytes memory allowlistData_
    ) internal virtual override {
        // Check that the parameters are of the correct length
        if (allowlistData_.length != 64) {
            revert Callback_InvalidParams();
        }

        // Decode the params to get the token contract and balance threshold
        (ITokenBalance token, uint96 threshold) =
            abi.decode(allowlistData_, (ITokenBalance, uint96));

        // Token must be a contract
        if (address(token).code.length == 0) revert Callback_InvalidParams();

        // Try to get balance for token, revert if it fails
        try token.balanceOf(address(this)) returns (uint256) {}
        catch {
            revert Callback_InvalidParams();
        }

        // Set the lot check
        tokenCheck = TokenCheck(token, threshold);
    }

    /// @inheritdoc BaselineAxisLaunch
    ///
    /// @param      callbackData_   abi-encoded data
    function _onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Validate that the buyer is allowed to participate
        _canParticipate(buyer_);

        // Call any additional implementation-specific logic
        __onBid(lotId_, bidId_, buyer_, amount_, callbackData_);
    }

    /// @notice Override this function to implement additional functionality for the `onBid` callback
    ///
    /// @param  lotId_          The ID of the lot
    /// @param  bidId_          The ID of the bid
    /// @param  buyer_          The address of the buyer
    /// @param  amount_         The amount of quote tokens
    /// @param  callbackData_   The callback data
    function __onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual {}

    // ========== INTERNAL FUNCTIONS ========== //

    function _canParticipate(address buyer_) internal view {
        // Check if the buyer's balance is above the threshold
        if (tokenCheck.token.balanceOf(buyer_) < tokenCheck.threshold) {
            revert Callback_NotAuthorized();
        }
    }
}
