/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script} from "lib/forge-std/src/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {WithSalts} from "script/salts/WithSalts.s.sol";

import {MockCallback} from "test/callbacks/MockCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {CappedMerkleAllowlist} from "src/callbacks/allowlists/CappedMerkleAllowlist.sol";
import {UniswapV2DirectToLiquidity} from "src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";

contract TestSalts is Script, WithEnvironment, Permit2User, WithSalts {
    // TODO shift into abstract contract that tests also inherit from
    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0x095b215677db999c3A268c16A31b15A28B2e572F);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0x8e530929af28C6aE9d9B24bF18c4447D23caE14a);
    address internal constant _GUNI_FACTORY = address(0x58Abf7Ea167B7234a3eFc4b043Cd6C9145f62f78);

    string internal constant _MOCK_CALLBACK = "MockCallback";
    string internal constant _CAPPED_MERKLE_ALLOWLIST = "CappedMerkleAllowlist";

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();
    }

    function generate(string calldata chain_) public {
        _setUp(chain_);

        _generateMockCallback();
        _generateCappedMerkleAllowlist();
        _generateUniswapV2DTL();
        _generateUniswapV3DTL();
    }

    function _generateMockCallback() internal {
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
                onClaimProceeds: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            _SELLER
        );
        bytes memory contractCode = type(MockCallback).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setSalt(bytecodePath, "98", _MOCK_CALLBACK, bytecodeHash);

        // 11111111 = 0xFF
        args = abi.encode(
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
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setSalt(bytecodePath, "FF", _MOCK_CALLBACK, bytecodeHash);

        // 11111101 = 0xFD
        args = abi.encode(
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
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setSalt(bytecodePath, "FD", _MOCK_CALLBACK, bytecodeHash);

        // 11111110 = 0xFE
        args = abi.encode(
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
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setSalt(bytecodePath, "FE", _MOCK_CALLBACK, bytecodeHash);

        // 11111100 = 0xFC
        args = abi.encode(
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
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setSalt(bytecodePath, "FC", _MOCK_CALLBACK, bytecodeHash);

        // 00000000 - 0x00
        args = abi.encode(
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
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setSalt(bytecodePath, "00", _MOCK_CALLBACK, bytecodeHash);

        // 00000010 - 0x02
        args = abi.encode(
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
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_MOCK_CALLBACK, contractCode, args);
        _setSalt(bytecodePath, "02", _MOCK_CALLBACK, bytecodeHash);
    }

    function _generateCappedMerkleAllowlist() internal {
        // 10001000 = 0x88
        bytes memory args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: true,
                onClaimProceeds: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            _SELLER
        );
        bytes memory contractCode = type(CappedMerkleAllowlist).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(_CAPPED_MERKLE_ALLOWLIST, contractCode, args);
        _setSalt(bytecodePath, "88", _CAPPED_MERKLE_ALLOWLIST, bytecodeHash);

        // 10010000 = 0x90
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: false,
                onClaimProceeds: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            _SELLER
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_CAPPED_MERKLE_ALLOWLIST, contractCode, args);
        _setSalt(bytecodePath, "90", _CAPPED_MERKLE_ALLOWLIST, bytecodeHash);
    }

    function _generateUniswapV2DTL() internal {
        bytes memory args =
            abi.encode(_AUCTION_HOUSE, _SELLER, _UNISWAP_V2_FACTORY, _UNISWAP_V2_ROUTER);
        bytes memory contractCode = type(UniswapV2DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("UniswapV2DirectToLiquidity", contractCode, args);
        _setSalt(bytecodePath, "E6", "UniswapV2DirectToLiquidity", bytecodeHash);
    }

    function _generateUniswapV3DTL() internal {
        bytes memory args = abi.encode(_AUCTION_HOUSE, _SELLER, _UNISWAP_V3_FACTORY, _GUNI_FACTORY);
        bytes memory contractCode = type(UniswapV3DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("UniswapV3DirectToLiquidity", contractCode, args);
        _setSalt(bytecodePath, "E6", "UniswapV3DirectToLiquidity", bytecodeHash);
    }
}
