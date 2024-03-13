// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICallback} from "src/interfaces/ICallback.sol";

/// @notice Library for handling callbacks
/// @dev This library is based on the design of UniswapV4's Hooks library (https://github.com/Uniswap/v4-core/blob/main/src/libraries/Hooks.sol)
/// and is published under the same MIT license.
/// We use the term callbacks because it is more appropriate for the type of extensibility we are providing to the Axis auction system.
/// The system decides whether to invoke specific hooks by inspecting the leading bits (first byte)
/// of the address that the callbacks contract is deployed to.
/// For example, a callbacks contract deployed to address: 0x9000000000000000000000000000000000000000
/// has leading bits '1001' which would cause the 'onCreate' and 'onPurchase' callbacks to be used.
/// There are 8 flags
library Callbacks {
    using Callbacks for ICallback;

    uint256 internal constant ON_CREATE_FLAG = 1 << 159;
    uint256 internal constant ON_CANCEL_FLAG = 1 << 158;
    uint256 internal constant ON_CURATE_FLAG = 1 << 157;
    uint256 internal constant ON_PURCHASE_FLAG = 1 << 156;
    uint256 internal constant ON_BID_FLAG = 1 << 155;
    uint256 internal constant ON_CLAIM_PROCEEDS_FLAG = 1 << 154;
    uint256 internal constant RECEIVE_QUOTE_TOKENS_FLAG = 1 << 153;
    uint256 internal constant SEND_BASE_TOKENS_FLAG = 1 << 152;

    struct Permissions {
        bool onCreate;
        bool onCancel;
        bool onCurate;
        bool onPurchase;
        bool onBid;
        bool onClaimProceeds;
        bool receiveQuoteTokens;
        bool sendBaseTokens;
    }

    /// @notice Thrown if the address will not lead to the specified callbacks being called
    /// @param callbacks The address of the callbacks contract
    error CallbacksAddressNotValid(address callbacks);

    /// @notice Callback did not return its selector
    error InvalidCallbackResponse();

    /// @notice thrown when a callback fails
    error FailedCallback();

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hooks address causes the intended hooks to be called
    /// @param permissions The hooks that are intended to be called
    /// @dev permissions param is memory as the function will be called from constructors
    function validateCallbacksPermissions(
        ICallback self,
        Permissions memory permissions
    ) internal pure {
        if (
            permissions.onCreate != self.hasPermission(ON_CREATE_FLAG)
                || permissions.onCancel != self.hasPermission(ON_CANCEL_FLAG)
                || permissions.onCurate != self.hasPermission(ON_CURATE_FLAG)
                || permissions.onPurchase != self.hasPermission(ON_PURCHASE_FLAG)
                || permissions.onBid != self.hasPermission(ON_BID_FLAG)
                || permissions.onClaimProceeds != self.hasPermission(ON_CLAIM_PROCEEDS_FLAG)
                || permissions.receiveQuoteTokens != self.hasPermission(RECEIVE_QUOTE_TOKENS_FLAG)
                || permissions.sendBaseTokens != self.hasPermission(SEND_BASE_TOKENS_FLAG)
        ) {
            revert CallbacksAddressNotValid(address(self));
        }
    }

    /// @notice Ensures that the callbacks contract includes at least one of the required flags and more if sending/receiving tokens
    /// @param callbacks The callbacks contract to verify
    function isValidCallbacksAddress(ICallback callbacks) internal pure returns (bool) {
        // Ensure that if the contract is expected to send base tokens, then it implements atleast onCreate and onCurate OR onPurchase (atomic auctions may not be prefunded).
        if (
            callbacks.hasPermission(SEND_BASE_TOKENS_FLAG)
                && (
                    !callbacks.hasPermission(ON_CREATE_FLAG) || !callbacks.hasPermission(ON_CURATE_FLAG)
                ) && !callbacks.hasPermission(ON_PURCHASE_FLAG)
        ) {
            return false;
        }

        // Ensure that, if not the zero address, atleast one of the callback functions is implemented or the contract is set to receive quote tokens (which can be done without implementing anything else)
        return address(callbacks) == address(0) || uint160(address(callbacks)) >= 1 << 153;
    }

    /// @notice performs a call using the given calldata on the given callback
    function callback(ICallback self, bytes memory data) internal {
        bytes4 expectedSelector;
        assembly {
            expectedSelector := mload(add(data, 0x20))
        }

        (bool success, bytes memory result) = address(self).call(data);
        if (!success) _revert(result);

        bytes4 selector = abi.decode(result, (bytes4));

        if (selector != expectedSelector) {
            revert InvalidCallbackResponse();
        }
    }

    /// @notice calls onCreate callback if permissioned and validates return value
    function onCreate(
        ICallback self,
        uint96 lotId,
        address seller,
        address baseToken,
        address quoteToken,
        uint96 capacity,
        bool preFund,
        bytes calldata callbackData
    ) internal {
        if (self.hasPermission(ON_CREATE_FLAG)) {
            self.callback(
                abi.encodeWithSelector(
                    ICallback.onCreate.selector,
                    lotId,
                    seller,
                    baseToken,
                    quoteToken,
                    capacity,
                    preFund,
                    callbackData
                )
            );
        }
    }

    /// @notice calls onCancel callback if permissioned and validates return value
    function onCancel(
        ICallback self,
        uint96 lotId,
        uint96 refund,
        bool preFunded,
        bytes calldata callbackData
    ) internal {
        if (self.hasPermission(ON_CANCEL_FLAG)) {
            self.callback(
                abi.encodeWithSelector(
                    ICallback.onCancel.selector, lotId, refund, preFunded, callbackData
                )
            );
        }
    }

    /// @notice calls onCurate callback if permissioned and validates return value
    function onCurate(
        ICallback self,
        uint96 lotId,
        uint96 curatorFee,
        bool preFund,
        bytes calldata callbackData
    ) internal {
        if (self.hasPermission(ON_CURATE_FLAG)) {
            self.callback(
                abi.encodeWithSelector(
                    ICallback.onCurate.selector, lotId, curatorFee, preFund, callbackData
                )
            );
        }
    }

    /// @notice calls onPurchase callback if permissioned and validates return value
    function onPurchase(
        ICallback self,
        uint96 lotId,
        address buyer,
        uint96 amount,
        uint96 payout,
        bool preFunded,
        bytes calldata callbackData
    ) internal {
        if (self.hasPermission(ON_PURCHASE_FLAG)) {
            self.callback(
                abi.encodeWithSelector(
                    ICallback.onPurchase.selector,
                    lotId,
                    buyer,
                    amount,
                    payout,
                    preFunded,
                    callbackData
                )
            );
        }
    }

    /// @notice calls onBid callback if permissioned and validates return value
    function onBid(
        ICallback self,
        uint96 lotId,
        uint64 bidId,
        address buyer,
        uint96 amount,
        bytes calldata callbackData
    ) internal {
        if (self.hasPermission(ON_BID_FLAG)) {
            self.callback(
                abi.encodeWithSelector(
                    ICallback.onBid.selector, lotId, bidId, buyer, amount, callbackData
                )
            );
        }
    }

    /// @notice calls onClaimProceeds callback if permissioned and validates return value
    function onClaimProceeds(
        ICallback self,
        uint96 lotId,
        uint96 proceeds,
        uint96 refund,
        bytes calldata callbackData
    ) internal {
        if (self.hasPermission(ON_CLAIM_PROCEEDS_FLAG)) {
            self.callback(
                abi.encodeWithSelector(
                    ICallback.onClaimProceeds.selector, lotId, proceeds, refund, callbackData
                )
            );
        }
    }

    function hasPermission(ICallback self, uint256 flag) internal pure returns (bool) {
        return uint256(uint160(address(self))) & flag != 0;
    }

    /// @notice bubble up revert if present. Else throw FailedCallback error
    function _revert(bytes memory result) private pure {
        if (result.length > 0) {
            assembly {
                revert(add(0x20, result), mload(result))
            }
        } else {
            revert FailedCallback();
        }
    }
}
