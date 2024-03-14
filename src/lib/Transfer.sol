// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IPermit2} from "src/lib/permit2/interfaces/IPermit2.sol";

library Transfer {
    using SafeTransferLib for ERC20;

    uint256 internal constant _PERMIT2_PARAMS_LEN = 256;

    // ============ Data Structures ============ //

    /// @notice     Parameters used for Permit2 approvals
    struct Permit2Approval {
        uint48 deadline;
        uint256 nonce;
        bytes signature;
    }

    // ========== Errors ========== //

    error UnsupportedToken(address token_);

    error InvalidParams();

    // ============ Functions ============ //

    function approve(ERC20 token_, address spender_, uint256 amount_) public {
        token_.safeApprove(spender_, amount_);
    }

    /// @notice     Performs an ERC20 transfer of `token_` from the caller
    /// @dev        This function handles the following:
    ///             1. Checks that the user has granted approval to transfer the token
    ///             2. Transfers the token from the user
    ///             3. Checks that the transferred amount was received
    ///
    ///             This function reverts if:
    ///             - Approval has not been granted to this contract to transfer the token
    ///             - The token transfer fails
    ///             - The transferred amount is less than the requested amount
    ///
    /// @param      token_              Token to transfer
    /// @param      recipient_          Address of the recipient
    /// @param      amount_             Amount of tokens to transfer (in native decimals)
    /// @param      validateBalance_    Whether to validate the balance of the recipient
    function transfer(
        ERC20 token_,
        address recipient_,
        uint256 amount_,
        bool validateBalance_
    ) public {
        uint256 balanceBefore;
        if (validateBalance_ == true) {
            balanceBefore = token_.balanceOf(recipient_);
        }

        // Transfer the quote token from the user
        // `safeTransferFrom()` will revert upon failure or the lack of allowance or balance
        token_.safeTransfer(recipient_, amount_);

        // Check that it is not a fee-on-transfer token
        if (validateBalance_ == true && token_.balanceOf(recipient_) < balanceBefore + amount_) {
            revert UnsupportedToken(address(token_));
        }
    }

    /// @notice     Performs an ERC20 transferFrom of `token_` from the sender
    /// @dev        This function handles the following:
    ///             1. Checks that the user has granted approval to transfer the token
    ///             2. Transfers the token from the user
    ///             3. Checks that the transferred amount was received
    ///
    ///             This function reverts if:
    ///             - Approval has not been granted to this contract to transfer the token
    ///             - The token transfer fails
    ///             - The transferred amount is less than the requested amount
    ///
    /// @param      token_              Token to transfer
    /// @param      sender_             Address of the sender
    /// @param      recipient_          Address of the recipient
    /// @param      amount_             Amount of tokens to transfer (in native decimals)
    /// @param      validateBalance_    Whether to validate the balance of the recipient
    function transferFrom(
        ERC20 token_,
        address sender_,
        address recipient_,
        uint256 amount_,
        bool validateBalance_
    ) public {
        uint256 balanceBefore;
        if (validateBalance_ == true) {
            balanceBefore = token_.balanceOf(recipient_);
        }

        // Transfer the quote token from the user
        // `safeTransferFrom()` will revert upon failure or the lack of allowance or balance
        token_.safeTransferFrom(sender_, recipient_, amount_);

        // Check that it is not a fee-on-transfer token
        if (validateBalance_ == true && token_.balanceOf(recipient_) < balanceBefore + amount_) {
            revert UnsupportedToken(address(token_));
        }
    }

    function permit2TransferFrom(
        ERC20 token_,
        address permit2_,
        address sender_,
        address recipient_,
        uint256 amount_,
        Permit2Approval memory approval_,
        bool validateBalance_
    ) public {
        uint256 balanceBefore;
        if (validateBalance_ == true) {
            balanceBefore = token_.balanceOf(recipient_);
        }

        {
            // Use PERMIT2 to transfer the token from the user
            IPermit2(permit2_).permitTransferFrom(
                IPermit2.PermitTransferFrom(
                    IPermit2.TokenPermissions(address(token_), amount_),
                    approval_.nonce,
                    approval_.deadline
                ),
                IPermit2.SignatureTransferDetails({to: recipient_, requestedAmount: amount_}),
                sender_, // Spender of the tokens
                approval_.signature
            );
        }

        // Check that it is not a fee-on-transfer token
        if (validateBalance_ == true && token_.balanceOf(recipient_) < balanceBefore + amount_) {
            revert UnsupportedToken(address(token_));
        }
    }

    function permit2OrTransferFrom(
        ERC20 token_,
        address permit2_,
        address sender_,
        address recipient_,
        uint256 amount_,
        Permit2Approval memory approval_,
        bool validateBalance_
    ) public {
        // If a Permit2 approval signature is provided, use it to transfer the quote token
        if (permit2_ != address(0) && approval_.signature.length > 0) {
            permit2TransferFrom(
                token_, permit2_, sender_, recipient_, amount_, approval_, validateBalance_
            );
        }
        // Otherwise fallback to a standard ERC20 transfer
        else {
            transferFrom(token_, sender_, recipient_, amount_, validateBalance_);
        }
    }

    function decodePermit2Approval(bytes memory data_)
        public
        pure
        returns (Permit2Approval memory)
    {
        // If the length is 0, then approval is not provided
        if (data_.length == 0) {
            return Permit2Approval({nonce: 0, deadline: 0, signature: bytes("")});
        }

        // If the length is non-standard, it is invalid
        if (data_.length != _PERMIT2_PARAMS_LEN) revert InvalidParams();

        return abi.decode(data_, (Permit2Approval));
    }
}
