// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICallbacks} from "src/interfaces/ICallbacks.sol";

/// @notice Library for handling callbacks
/// @dev This library heavily leverages concepts from UniswapV4's Hooks library (https://github.com/Uniswap/v4-core/blob/main/src/libraries/Hooks.sol) 
/// and is offered under the same MIT license.
library Callbacks {
    using Callbacks for ICallbacks;

    bytes1 internal constant ON_CREATE_FLAG = bytes1(uint8(1 << 7));
    bytes1 internal constant ON_CANCEL_FLAG = bytes1(uint8(1 << 6));
    bytes1 internal constant ON_CURATE_FLAG = bytes1(uint8(1 << 5));
    bytes1 internal constant ON_PURCHASE_FLAG = bytes1(uint8(1 << 4));
    bytes1 internal constant ON_BID_FLAG = bytes1(uint8(1 << 3));
    bytes1 internal constant ON_SETTLE_FLAG = bytes1(uint8(1 << 2));
    bytes1 internal constant RECEIVE_QUOTE_TOKENS_FLAG = bytes1(uint8(1 << 1));
    bytes1 internal constant SEND_BASE_TOKENS_FLAG = bytes1(uint8(1));
    
    struct Config {
        bool onCreate;
        bool onCancel;
        bool onCurate;
        bool onPurchase;
        bool onBid;
        bool onSettle;
        bool sendBaseTokens;
        bool receiveQuoteTokens;
    }

    /// @notice Callback did not return its selector
    error InvalidCallbackResponse();

    /// @notice thrown when a callback fails
    error FailedCallback();

    /// @notice Ensures that the callbacks contract includes at least one of the required flags and more if sending/receiving tokens
    /// @param callbacks The callbacks to verify
    function isValidConfig(ICallbacks callbacks) internal view returns (bool) {
        
        bytes1 config = callbacks.CONFIG();

        // Ensure that atleast one of the callback functions is implemented or the contract is set to receive quote tokens (which can be done without implementing anything else)
        if (config >> 1 == 0) {
            return false;
        }

        // Ensure that if the contract is expected to send base tokens, then it implements atleast onCreate and onCurate OR onPurchase (atomic auctions may not be prefunded).
        if (config & SEND_BASE_TOKENS_FLAG != 0) {
            if ((config & ON_CREATE_FLAG == 0 || config & ON_CURATE_FLAG == 0) && config & ON_PURCHASE_FLAG == 0) {
                return false;
            }
        }

        return true;
    }

    /// @notice performs a call using the given calldata on the given callback
    function callback(ICallbacks self, bytes memory data) internal {
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
    function onCreate(ICallbacks self, uint96 lotId, address seller, address baseToken, address quoteToken, uint96 capacity, bool preFund, bytes calldata callbackData)
        internal
    {
        if (self.hasPermission(ON_CREATE_FLAG)) {
            self.callback(
                abi.encodeWithSelector(ICallbacks.onCreate.selector, lotId, seller, baseToken, quoteToken, capacity, preFund, callbackData)
            );
        }
    }

    /// @notice calls onCancel callback if permissioned and validates return value
    function onCancel(ICallbacks self, uint96 lotId, uint96 refund, bool preFunded, bytes calldata callbackData) internal {
        if (self.hasPermission(ON_CANCEL_FLAG)) {
            self.callback(
                abi.encodeWithSelector(ICallbacks.onCancel.selector, lotId, refund, preFunded, callbackData)
            );

        }
    }

    /// @notice calls onCurate callback if permissioned and validates return value
    function onCurate(ICallbacks self, uint96 lotId, uint96 curatorFee, bool preFund, bytes calldata callbackData) internal {
        if (self.hasPermission(ON_CURATE_FLAG)) {
            self.callback(
                abi.encodeWithSelector(ICallbacks.onCurate.selector, lotId, curatorFee, preFund, callbackData)
            );
        }
    }

    /// @notice calls onPurchase callback if permissioned and validates return value
    function onPurchase(ICallbacks self, uint96 lotId, address buyer, uint96 amount, uint96 payout, bool preFunded, bytes calldata callbackData)
        internal
    {
        if (self.hasPermission(ON_PURCHASE_FLAG)) {
            self.callback(
                abi.encodeWithSelector(ICallbacks.onPurchase.selector, lotId, buyer, amount, payout, preFunded, callbackData)
            );

        }
    }

    /// @notice calls onBid callback if permissioned and validates return value
    function onBid(ICallbacks self, uint96 lotId, uint64 bidId, address buyer, uint96 amount, bytes calldata callbackData)
        internal
    {
        if (self.hasPermission(ON_BID_FLAG)) {
            self.callback(
                abi.encodeWithSelector(ICallbacks.onBid.selector, lotId, bidId, buyer, amount, callbackData)
            );
        }
    }

    /// @notice calls onSettle callback if permissioned and validates return value
    function onSettle(ICallbacks self, uint96 lotId, uint96 proceeds, uint96 refund, bytes calldata callbackData, bytes memory auctionOutput)
        internal
    {
        if (self.hasPermission(ON_SETTLE_FLAG)) {
            self.callback(
                abi.encodeWithSelector(ICallbacks.onSettle.selector, lotId, proceeds, refund, callbackData, auctionOutput)
            );
        }
    }

    function hasPermission(ICallbacks self, bytes1 flag) internal view returns (bool) {
        // TODO extra external call since we aren't storing the config in the first byte of the address, maybe reconsider
        return self.CONFIG() & flag != 0;
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