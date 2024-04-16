// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Callbacks} from "src/lib/Callbacks.sol";
import {ICallback} from "src/interfaces/ICallback.sol";

import {MockCallback} from "test/callbacks/MockCallback.sol";

import {Test} from "forge-std/Test.sol";

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
            bytes32(0x6a3b1897dfa202b73e46842314d76d2936e1abd3bbef472d3f55aa65a3e8dbba), permissions
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
            bytes32(0x2ad269c1a5996dd43f85791da9c4af5ea1edaae9717cf0fd4e0c9590a92e073f), permissions
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
            bytes32(0xd6d44ea0b5b5ffe0b8836765deaf24ebfd32d1ae0cc1a1e13824edd1475db555), permissions
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
            bytes32(0x8f9c21d7e8f3f9d4a0a58fd0a63b977dee1eac624b511d9bb82e216a14c1859f), permissions
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
            bytes32(0xc6000206f8d0f47448729fb2260bc839d3b38ee37351022bf163eeddb9cde8a7), permissions
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
            bytes32(0xac178f4c3530ff125e82a31c8b52a8bd81cbefd1e69abcbc892b98c25513cc04), permissions
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
            bytes32(0x0634e082cc1110c4dd927edf5eb6eab0ada8702967efcd3742c9f6cc08aa7b7f), permissions
        );
    }

    function _receiveQuoteTokensSalt() internal returns (bytes32, Callbacks.Permissions memory) {
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
            bytes32(0xec0268f42513781494874314f3b66fb96fc32781e8892aa004dae2e8e32252ce), permissions
        );
    }

    function _sendBaseTokensSalt() internal returns (bytes32, Callbacks.Permissions memory) {
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
            bytes32(0x4b5e4bfb81663a913023870fdb4b4406dcfdf186fa41ba545877b67eb4a8c77c), permissions
        );
    }

    function _sendBaseTokens_onCreateSalt()
        internal
        returns (bytes32, Callbacks.Permissions memory)
    {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        // // 10000001 = 0x81
        // // cast create2 -s 81 -i $(cat ./bytecode/MockCallback81.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback81.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0x0166b394e13c196df4b63e4594544834b6a2f0ccc0c3eed3f1e4e193f82c8835), permissions
        );
    }

    function _sendBaseTokens_onCurateSalt()
        internal
        returns (bytes32, Callbacks.Permissions memory)
    {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: true,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        // // 00100001 = 0x21
        // // cast create2 -s 21 -i $(cat ./bytecode/MockCallback21.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback21.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0x00ebf270f49802ee0f5283b961cb84b40afeae4c1fd86dc4808a0c3cf5a2371a), permissions
        );
    }

    function _sendBaseTokens_onCreate_onCurateSalt()
        internal
        returns (bytes32, Callbacks.Permissions memory)
    {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: true,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        // // 10100001 = 0xA1
        // // cast create2 -s A1 -i $(cat ./bytecode/MockCallbackA1.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallbackA1.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0xa7b865214acf848c64d628bc01200e2925ed893b58b437f3664525b78d93b6d2), permissions
        );
    }

    function _sendBaseTokens_onPurchaseSalt()
        internal
        returns (bytes32, Callbacks.Permissions memory)
    {
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: false,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: false,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: true
        });

        // // 00010001 = 0x11
        // // cast create2 -s 11 -i $(cat ./bytecode/MockCallback11.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(_AUCTION_HOUSE, permissions, _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback11.bin",
        //     vm.toString(bytecode)
        // );

        return (
            bytes32(0xe5228f9ba15e580011a7c74760aa4fa71ac0c6cf42166f6025d37d7d09c752cf), permissions
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
        (bytes32 salt, Callbacks.Permissions memory permissions) = _receiveQuoteTokensSalt();
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
        (bytes32 salt, Callbacks.Permissions memory permissions) = _sendBaseTokensSalt();
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

    function test_isValidCallbacksAddress_onClaimProceeds() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onClaimProceedsSalt();
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
