/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {MockCallback} from "test/callbacks/MockCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

contract TestSalts is Script, WithEnvironment, Permit2User {
    // TODO shift into abstract contract that tests also inherit from
    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
    }

    function generate(string calldata chain_) public {
        _setUp(chain_);

        // Allowlist callback supports onCreate, onPurchase, and onBid callbacks
        // 10011000 = 0x98
        // cast create2 -s 98 -i $(cat ./bytecode/MockCallback98.bin)
        bytes memory bytecode = abi.encodePacked(
            type(MockCallback).creationCode,
            abi.encode(
                _AUCTION_HOUSE,
                Callbacks.Permissions({
                    onCreate: true,
                    onCancel: false,
                    onCurate: false,
                    onPurchase: true,
                    onBid: true,
                    onClaimProceeds: false,
                    receiveQuoteTokens: false,
                    sendBaseTokens: false
                }),
                _SELLER
            )
        );
        vm.writeFile("./bytecode/MockCallback98.bin", vm.toString(bytecode));
        console2.log("MockCallback bytecode written to ./bytecode/MockCallback98.bin");

        // 11111111 = 0xFF
        bytecode = abi.encodePacked(
            type(MockCallback).creationCode,
            abi.encode(
                _AUCTION_HOUSE,
                Callbacks.Permissions({
                    onCreate: true,
                    onCancel: true,
                    onCurate: true,
                    onPurchase: true,
                    onBid: true,
                    onClaimProceeds: true,
                    receiveQuoteTokens: true,
                    sendBaseTokens: true
                }),
                _SELLER
            )
        );
        vm.writeFile("./bytecode/MockCallbackFF.bin", vm.toString(bytecode));
        console2.log("MockCallback bytecode written to ./bytecode/MockCallbackFF.bin");

        // 11111101 = 0xFD
        bytecode = abi.encodePacked(
            type(MockCallback).creationCode,
            abi.encode(
                _AUCTION_HOUSE,
                Callbacks.Permissions({
                    onCreate: true,
                    onCancel: true,
                    onCurate: true,
                    onPurchase: true,
                    onBid: true,
                    onClaimProceeds: true,
                    receiveQuoteTokens: false,
                    sendBaseTokens: true
                }),
                _SELLER
            )
        );
        vm.writeFile("./bytecode/MockCallbackFD.bin", vm.toString(bytecode));
        console2.log("MockCallback bytecode written to ./bytecode/MockCallbackFD.bin");

        // 11111110 = 0xFE
        bytecode = abi.encodePacked(
            type(MockCallback).creationCode,
            abi.encode(
                _AUCTION_HOUSE,
                Callbacks.Permissions({
                    onCreate: true,
                    onCancel: true,
                    onCurate: true,
                    onPurchase: true,
                    onBid: true,
                    onClaimProceeds: true,
                    receiveQuoteTokens: true,
                    sendBaseTokens: false
                }),
                _SELLER
            )
        );
        vm.writeFile("./bytecode/MockCallbackFE.bin", vm.toString(bytecode));
        console2.log("MockCallback bytecode written to ./bytecode/MockCallbackFE.bin");

        // 11111100 = 0xFC
        bytecode = abi.encodePacked(
            type(MockCallback).creationCode,
            abi.encode(
                _AUCTION_HOUSE,
                Callbacks.Permissions({
                    onCreate: true,
                    onCancel: true,
                    onCurate: true,
                    onPurchase: true,
                    onBid: true,
                    onClaimProceeds: true,
                    receiveQuoteTokens: false,
                    sendBaseTokens: false
                }),
                _SELLER
            )
        );
        vm.writeFile("./bytecode/MockCallbackFC.bin", vm.toString(bytecode));
        console2.log("MockCallback bytecode written to ./bytecode/MockCallbackFC.bin");

        // 00000000 - 0x00
        bytecode = abi.encodePacked(
            type(MockCallback).creationCode,
            abi.encode(
                _AUCTION_HOUSE,
                Callbacks.Permissions({
                    onCreate: false,
                    onCancel: false,
                    onCurate: false,
                    onPurchase: false,
                    onBid: false,
                    onClaimProceeds: false,
                    receiveQuoteTokens: false,
                    sendBaseTokens: false
                }),
                _SELLER
            )
        );
        vm.writeFile("./bytecode/MockCallback00.bin", vm.toString(bytecode));
        console2.log("MockCallback bytecode written to ./bytecode/MockCallback00.bin");

        // 00000010 - 0x02
        bytecode = abi.encodePacked(
            type(MockCallback).creationCode,
            abi.encode(
                _AUCTION_HOUSE,
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
                _SELLER
            )
        );
        vm.writeFile("./bytecode/MockCallback02.bin", vm.toString(bytecode));
        console2.log("MockCallback bytecode written to ./bytecode/MockCallback02.bin");
    }
}
