// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Callbacks} from "src/lib/Callbacks.sol";
import {ICallback} from "src/interfaces/ICallback.sol";

import {MockCallback} from "test/callbacks/MockCallback.sol";

import {Test} from "forge-std/Test.sol";

import {console2} from "forge-std/console2.sol";

contract CallbacksTest is Test {
    using Callbacks for ICallback;

    address internal constant _AUCTION_HOUSE = address(0x1);
    address internal constant _SELLER = address(0x2);

    function _allFalseSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // // 00000000 = 0x00
        // // cast create2 -s 00 -i $(cat ./bytecode/MockCallback00.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback00.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0x6274afc3961fb1fd4c1fc9ea6b09fee8682f3834d237bfbe08f18dd482f859e5), permissions
        );
    }

    function _onCreateSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // // 10000000 = 0x80
        // // cast create2 -s 80 -i $(cat ./bytecode/MockCallback80.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback80.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0xc950537943697bd7a8b1ea4f9d5dee17ead88f1941822672cd7ba50f6a48346b), permissions
        );
    }

    function _onCancelSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: true,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // // 01000000 = 0x40
        // // cast create2 -s 40 -i $(cat ./bytecode/MockCallback40.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback40.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0xcffeb355ea15c46babdec92cc6744d0ead33efd4fdf52708a1adc815e7295864), permissions
        );
    }

    function _onCurateSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: true,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // // 00100000 = 0x20
        // // cast create2 -s 20 -i $(cat ./bytecode/MockCallback20.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback20.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0xfc1a363591cfc7264e926cde5d34c9d8089cb0657680cb5888e3dfd44733e699), permissions
        );
    }

    function _onPurchaseSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // // 00010000 = 0x10
        // // cast create2 -s 10 -i $(cat ./bytecode/MockCallback10.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback10.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0x953c7dd5dc479cf1b0b0178e10ec218436ed4e738234a5b88d70b8fd4d7ad4d8), permissions
        );
    }

    function _onBidSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: true,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // // 00001000 = 0x08
        // // cast create2 -s 08 -i $(cat ./bytecode/MockCallback08.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback08.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0xd466651502b03fc17fe2da3ae976e2704eb4ba6cc1f8773797c6d126e19236f7), permissions
        );
    }

    function _onClaimProceedsSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: true,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // // 00000100 = 0x04
        // // cast create2 -s 04 -i $(cat ./bytecode/MockCallback04.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback04.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0x21885aedd62feb2a6500b3a5ac4f8e54fae00c959070c3f45bce4828e7d3d9c9), permissions
        );
    }

    function _onReceiveQuoteTokensSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: true,
            sendBaseTokens: false
        });

        // // 00000010 = 0x02
        // // cast create2 -s 02 -i $(cat ./bytecode/MockCallback02.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback02.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0xe9922fa3f41d7ba26a8bc3be2865413fa6912f5434f21ebc2f380a0cc34d78c5), permissions
        );
    }

    function _onSendBaseTokensSalt() internal returns (bytes32, Callbacks.Permissions memory) {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        // // 00000001 = 0x01
        // // cast create2 -s 01 -i $(cat ./bytecode/MockCallback01.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback01.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0x3f7e7126965c5f52a65d963ad59b2817e87f47da8546d247f8f4da68bc193faf), permissions
        );
    }

    // validateCallbacksPermissions
    // [X] all false
    // [X] onCreate is true
    // [X] onCancel is true
    // [X] onCurate is true
    // [X] onPurchase is true
    // [X] onBid is true
    // [X] onClaimProceeds is true
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
                onClaimProceeds: false,
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
                onClaimProceeds: false,
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
                onClaimProceeds: false,
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
                onClaimProceeds: false,
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
                onClaimProceeds: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            permissions_.onBid
        );

        // onClaimProceeds
        _assertValidateCallbacksPermission(
            callback_,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onClaimProceeds: true,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            permissions_.onClaimProceeds
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
                onClaimProceeds: false,
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
                onClaimProceeds: false,
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

    function test_validateCallbacksPermissions_onClaimProceeds() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onClaimProceedsSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onReceiveQuoteTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onReceiveQuoteTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        _assertValidateCallbacksPermissions(callback, permissions);
    }

    function test_validateCallbacksPermissions_onSendBaseTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onSendBaseTokensSalt();
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
        MockCallback callback = new MockCallback{salt: salt_}(_AUCTION_HOUSE, permissions_, _SELLER);
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
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
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
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
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
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
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
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
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
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
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
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_onClaimProceeds() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onClaimProceedsSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), true, "onClaimProceeds");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_receiveQuoteTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onReceiveQuoteTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), true, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_sendBaseTokens() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onSendBaseTokensSalt();
        ICallback callback = _createCallback(salt, permissions);

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
        assertEq(
            callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens"
        );
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), true, "sendBaseTokens");
    }

    // isValidCallbacksAddress
    // [ ] zero address
    // [ ] if no flags are set, revert
    // [ ] if only RECEIVE_QUOTE_TOKENS_FLAG is set, return true
    // [ ] if any callback function is set, return true
}
