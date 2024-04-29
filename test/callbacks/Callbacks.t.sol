// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Callbacks} from "src/lib/Callbacks.sol";
import {ICallback} from "src/interfaces/ICallback.sol";

import {MockCallback} from "test/callbacks/MockCallback.sol";

import {Test} from "forge-std/Test.sol";
import {WithSalts} from "test/lib/WithSalts.sol";

contract CallbacksTest is Test, WithSalts {
    using Callbacks for ICallback;

    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);

    function _getMockCallbackSalt(Callbacks.Permissions memory permissions_)
        internal
        returns (bytes32)
    {
        bytes memory args = abi.encode(_AUCTION_HOUSE, permissions_);
        return _getTestSalt("MockCallback", type(MockCallback).creationCode, args);
    }

    function _allFalseSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        // 00000000 - 0x00
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _onCreateSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        // 10000000 = 0x80
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _onCancelSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        // 01000000 = 0x40
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: true,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _onCurateSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        // 00100000 = 0x20
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: true,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _onPurchaseSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        // 00010000 = 0x10
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _onBidSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        // 00001000 = 0x08
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _onSettleSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onSettle: true,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _receiveQuoteTokensSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        // 00000010 = 0x02
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: true,
            sendBaseTokens: false
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _sendBaseTokensSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        // 00000001 = 0x01
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _sendBaseTokens_onCreateSalt()
        internal
        returns (bytes32, Callbacks.Permissions memory)
    {
        // 10000001 = 0x81
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _sendBaseTokens_onCurateSalt()
        internal
        returns (bytes32, Callbacks.Permissions memory)
    {
        // 00100001 = 0x21
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: true,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _sendBaseTokens_onCreate_onCurateSalt()
        internal
        returns (bytes32, Callbacks.Permissions memory)
    {
        // 10100001 = 0xA1
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: true,
            onPurchase: false,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    function _sendBaseTokens_onPurchaseSalt()
        internal
        returns (bytes32, Callbacks.Permissions memory)
    {
        // 00010001 = 0x11
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        return (_getMockCallbackSalt(permissions), permissions);
    }

    // validateCallbacksPermissions
    // [X] all false
    // [X] onCreate is true
    // [X] onCancel is true
    // [X] onCurate is true
    // [X] onPurchase is true
    // [X] onBid is true
    // [X] onSettle is true
    // [X] receiveQuoteTokens is true
    // [X] sendBaseTokens is true

    function _assertValidateCallbacksPermission(
        ICallback callback_,
        Callbacks.Permissions memory permissions_,
        bool expectValid_
    ) internal {
        if (!expectValid_) {
            bytes memory err = abi.encodeWithSelector(
                Callbacks.CallbacksAddressNotValid.selector, address(callback_)
            );
            vm.expectRevert(err);
        }

        callback_.validateCallbacksPermissions(permissions_);
    }

    function _assertValidateCallbacksPermissions(
        ICallback callback_,
        Callbacks.Permissions memory permissions_
    ) internal {
        // Iterate through all the permissions and check if they match the callback's permissions

        // onCreate
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            permissions_.onCreate
        );

        // onCancel
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: true,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            permissions_.onCancel
        );

        // onCurate
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: true,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            permissions_.onCurate
        );

        // onPurchase
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            permissions_.onPurchase
        );

        // onBid
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: true,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            permissions_.onBid
        );

        // onSettle
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: true,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            permissions_.onSettle
        );

        // receiveQuoteTokens
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: true,
                sendBaseTokens: false
            }),
            permissions_.receiveQuoteTokens
        );

        // sendBaseTokens
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: true
            }),
            permissions_.sendBaseTokens
        );
    }

    function test_validateCallbacksPermissions_allFalse() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _allFalseSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onCreate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCreateSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onCancel() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCancelSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onCurate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCurateSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onPurchase() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onPurchaseSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onBid() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onBidSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onSettle() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onSettleSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onReceiveQuoteTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _receiveQuoteTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onSendBaseTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _sendBaseTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    // hasPermission
    // [X] all false
    // [X] ON_CREATE_FLAG
    // [X] ON_CANCEL_FLAG
    // [X] ON_CURATE_FLAG
    // [X] ON_PURCHASE_FLAG
    // [X] ON_BID_FLAG
    // [X] ON_CLAIM_PROCEEDS_FLAG
    // [X] RECEIVE_QUOTE_TOKENS_FLAG
    // [X] SEND_BASE_TOKENS_FLAG

    function _createCallback(
        bytes32 salt_,
        Callbacks.Permissions memory permissions_
    ) internal returns (ICallback) {
        vm.startBroadcast();
        MockCallback callback = new MockCallback{salt: salt_}(_AUCTION_HOUSE, permissions_);
        vm.stopBroadcast();

        return callback;
    }

    function test_hasPermission_allFalse() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _allFalseSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), false, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_onCreate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCreateSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), true, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), false, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_onCancel() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCancelSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), true, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), false, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_onCurate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCurateSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), true, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), false, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_onPurchase() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onPurchaseSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), true, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), false, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_onBid() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onBidSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), true, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), false, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_onSettle() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onSettleSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), true, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_receiveQuoteTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _receiveQuoteTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), false, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), true, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_sendBaseTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _sendBaseTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_SETTLE_FLAG), false, "onSettle");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), true, "sendBaseTokens");
    }

    // isValidCallbacksAddress
    // [X] zero address
    // [X] when send base tokens flag is set
    //  [X] when onCreate is set
    //   [X] it returns false
    //  [X] when onCurate is set
    //   [X] when onCreate is set
    //    [X] it returns true
    //   [X] it returns false
    //  [X] when onPurchase is set
    //   [X] it returns true
    //  [X] it returns false
    // [X] if no flags are set, revert
    // [X] if only RECEIVE_QUOTE_TOKENS_FLAG is set, return true
    // [X] if any callback function is set, return true

    function test_isValidCallbacksAddress_zero() public {
        ICallback callback = ICallback(address(0));

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_allFalse() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _allFalseSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), false, "invalid");
    }

    function test_isValidCallbacksAddress_onCreate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCreateSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_onCancel() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCancelSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_onCurate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCurateSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_onPurchase() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onPurchaseSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_onBid() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onBidSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_onSettle() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onSettleSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_receiveQuoteTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _receiveQuoteTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_sendBaseTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _sendBaseTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), false, "valid");
    }

    function test_isValidCallbacksAddress_sendBaseTokens_onCreate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _sendBaseTokens_onCreateSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), false, "invalid");
    }

    function test_isValidCallbacksAddress_sendBaseTokens_onCurate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _sendBaseTokens_onCurateSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), false, "invalid");
    }

    function test_isValidCallbacksAddress_sendBaseTokens_onCreate_onCurate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) =
            _sendBaseTokens_onCreate_onCurateSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }

    function test_isValidCallbacksAddress_sendBaseTokens_onPurchase() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _sendBaseTokens_onPurchaseSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.isValidCallbacksAddress(), true, "invalid");
    }
}
