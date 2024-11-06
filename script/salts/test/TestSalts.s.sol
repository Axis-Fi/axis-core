/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script} from "@forge-std-1.9.1/Script.sol";
import {WithEnvironment} from "../../deploy/WithEnvironment.s.sol";
import {Permit2User} from "../../../test/lib/permit2/Permit2User.sol";
import {WithSalts} from "../WithSalts.s.sol";

import {MockCallback} from "../../../test/callbacks/MockCallback.sol";
import {Callbacks} from "../../../src/lib/Callbacks.sol";

import {TestConstants} from "../../../test/Constants.sol";

contract TestSalts is Script, WithEnvironment, Permit2User, WithSalts, TestConstants {
    string internal constant _MOCK_CALLBACK = "MockCallback";

    function _setUp(
        string calldata chain_
    ) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();
    }

    function generate(string calldata chain_, string calldata saltKey_) public {
        _setUp(chain_);

        // For the given salt key, call the appropriate selector
        // e.g. a salt key named MockCallback would require the following function: generateMockCallback()
        bytes4 selector = bytes4(keccak256(bytes(string.concat("generate", saltKey_, "()"))));

        // Call the generate function for the salt key
        (bool success,) = address(this).call(abi.encodeWithSelector(selector));
        require(success, string.concat("Failed to generate ", saltKey_));
    }

    function generateMockCallback() public {
        // Allowlist callback supports onCreate, onPurchase, and onBid callbacks
        // 10011000 = 0x98
        // cast create2 -s 98 -i $(cat ./bytecode/MockCallback98.bin)
        bytes memory args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: true,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        bytes memory contractCode = type(MockCallback).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "98", _MOCK_CALLBACK, bytecodeHash);

        // 11111111 = 0xFF
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: true,
                onBid: true,
                onSettle: true,
                receiveQuoteTokens: true,
                sendBaseTokens: true
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "FF", _MOCK_CALLBACK, bytecodeHash);

        // 11111101 = 0xFD
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: true,
                onBid: true,
                onSettle: true,
                receiveQuoteTokens: false,
                sendBaseTokens: true
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "FD", _MOCK_CALLBACK, bytecodeHash);

        // 11111110 = 0xFE
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: true,
                onBid: true,
                onSettle: true,
                receiveQuoteTokens: true,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "FE", _MOCK_CALLBACK, bytecodeHash);

        // 11111100 = 0xFC
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: true,
                onBid: true,
                onSettle: true,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "FC", _MOCK_CALLBACK, bytecodeHash);

        // 00000000 - 0x00
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "00", _MOCK_CALLBACK, bytecodeHash);

        // 00000010 - 0x02
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: true,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "02", _MOCK_CALLBACK, bytecodeHash);

        // 10000000 = 0x80
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "80", _MOCK_CALLBACK, bytecodeHash);

        // 01000000 = 0x40
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: true,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "40", _MOCK_CALLBACK, bytecodeHash);

        // 00100000 = 0x20
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: true,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "20", _MOCK_CALLBACK, bytecodeHash);

        // 00010000 = 0x10
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "10", _MOCK_CALLBACK, bytecodeHash);

        // 00001000 = 0x08
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: true,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "08", _MOCK_CALLBACK, bytecodeHash);

        // 00000100 = 0x04
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: true,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "04", _MOCK_CALLBACK, bytecodeHash);

        // 00000010 = 0x02
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: true,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "02", _MOCK_CALLBACK, bytecodeHash);

        // 00000001 = 0x01
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: true
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "01", _MOCK_CALLBACK, bytecodeHash);

        // 10000001 = 0x81
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: true
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "81", _MOCK_CALLBACK, bytecodeHash);

        // 00100001 = 0x21
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: true,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: true
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "21", _MOCK_CALLBACK, bytecodeHash);

        // 10100001 = 0xA1
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: true,
                onPurchase: false,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: true
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "A1", _MOCK_CALLBACK, bytecodeHash);

        // 00010001 = 0x11
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: false,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: true
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setTestSalt(bytecodePath, "11", _MOCK_CALLBACK, bytecodeHash);
    }
}
