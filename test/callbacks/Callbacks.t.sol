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

        return (bytes32(0xc950537943697bd7a8b1ea4f9d5dee17ead88f1941822672cd7ba50f6a48346b), permissions);
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

        return (bytes32(0xcffeb355ea15c46babdec92cc6744d0ead33efd4fdf52708a1adc815e7295864), permissions);
    }

    // validateCallbacksPermissions
    // [ ] all false
    // [ ] onCreate is true
    // [ ] onCancel is true
    // [ ] onCurate is true
    // [ ] onPurchase is true
    // [ ] onBid is true
    // [ ] onClaimProceeds is true
    // [ ] receiveQuoteTokens is true
    // [ ] sendBaseTokens is true

    // hasPermission
    // [ ] ON_CREATE_FLAG
    // [ ] ON_CANCEL_FLAG
    // [ ] ON_CURATE_FLAG
    // [ ] ON_PURCHASE_FLAG
    // [ ] ON_BID_FLAG
    // [ ] ON_CLAIM_PROCEEDS_FLAG
    // [ ] RECEIVE_QUOTE_TOKENS_FLAG
    // [ ] SEND_BASE_TOKENS_FLAG

    function _createCallback(
        bytes32 salt_,
        Callbacks.Permissions memory permissions_
    ) internal returns (ICallback) {
        vm.startBroadcast();
        MockCallback callback = new MockCallback{salt: salt_}(
            _AUCTION_HOUSE,
            permissions_,
            _SELLER
        );
        vm.stopBroadcast();

        return callback;
    }

    function test_hasPermission_onCreate() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCreateSalt();
        ICallback callback = _createCallback(
            salt,
            permissions
        );

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), true, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), false, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
        assertEq(callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens");
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    function test_hasPermission_onCancel() public {
        (bytes32 salt, Callbacks.Permissions memory permissions) = _onCancelSalt();
        ICallback callback = _createCallback(
            salt,
            permissions
        );

        assertEq(callback.hasPermission(Callbacks.ON_CREATE_FLAG), false, "onCreate");
        assertEq(callback.hasPermission(Callbacks.ON_CANCEL_FLAG), true, "onCancel");
        assertEq(callback.hasPermission(Callbacks.ON_CURATE_FLAG), false, "onCurate");
        assertEq(callback.hasPermission(Callbacks.ON_PURCHASE_FLAG), false, "onPurchase");
        assertEq(callback.hasPermission(Callbacks.ON_BID_FLAG), false, "onBid");
        assertEq(callback.hasPermission(Callbacks.ON_CLAIM_PROCEEDS_FLAG), false, "onClaimProceeds");
        assertEq(callback.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG), false, "receiveQuoteTokens");
        assertEq(callback.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG), false, "sendBaseTokens");
    }

    // isValidCallbacksAddress
    // [ ] zero address
    // [ ] if no flags are set, revert
    // [ ] if only RECEIVE_QUOTE_TOKENS_FLAG is set, return true
    // [ ] if any callback function is set, return true

}