/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script} from "lib/forge-std/src/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {WithSalts} from "script/salts/WithSalts.s.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockCallback} from "test/callbacks/MockCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {CappedMerkleAllowlist} from "src/callbacks/allowlists/CappedMerkleAllowlist.sol";
import {UniswapV2DirectToLiquidity} from "src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";
import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {BALwithAllocatedAllowlist} from
    "src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";

contract TestSalts is Script, WithEnvironment, Permit2User, WithSalts {
    // TODO shift into abstract contract that tests also inherit from
    address internal constant _OWNER = address(0x1);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0x584A2a1F5eCdCDcB6c0616cd280a7Db89239872B);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0x43de928116768b88F8BF8f768b3de90A0Aaf9551);
    address internal constant _GUNI_FACTORY = address(0xc46b184e5521Cb87Fc5288Ff49D978A4BE4B055c);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xe9d3A46B2a5813eAED0ab1E2B955c29038545FbD);

    string internal constant _MOCK_CALLBACK = "MockCallback";
    string internal constant _CAPPED_MERKLE_ALLOWLIST = "CappedMerkleAllowlist";

    function _setUp(string calldata chain_) internal {
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

    function generateCappedMerkleAllowlist() public {
        // 10001000 = 0x88
        bytes memory args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
                onBid: true,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        bytes memory contractCode = type(CappedMerkleAllowlist).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(_CAPPED_MERKLE_ALLOWLIST, contractCode, args);
        _setTestSalt(bytecodePath, "88", _CAPPED_MERKLE_ALLOWLIST, bytecodeHash);

        // 10010000 = 0x90
        args = abi.encode(
            _AUCTION_HOUSE,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: false,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
        (bytecodePath, bytecodeHash) = _writeBytecode(_CAPPED_MERKLE_ALLOWLIST, contractCode, args);
        _setTestSalt(bytecodePath, "90", _CAPPED_MERKLE_ALLOWLIST, bytecodeHash);
    }

    function generateUniswapV2DirectToLiquidity() public {
        bytes memory args = abi.encode(_AUCTION_HOUSE, _UNISWAP_V2_FACTORY, _UNISWAP_V2_ROUTER);
        bytes memory contractCode = type(UniswapV2DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("UniswapV2DirectToLiquidity", contractCode, args);
        _setTestSalt(bytecodePath, "E6", "UniswapV2DirectToLiquidity", bytecodeHash);
    }

    function generateUniswapV3DirectToLiquidity() public {
        bytes memory args = abi.encode(_AUCTION_HOUSE, _UNISWAP_V3_FACTORY, _GUNI_FACTORY);
        bytes memory contractCode = type(UniswapV3DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("UniswapV3DirectToLiquidity", contractCode, args);
        _setTestSalt(bytecodePath, "E6", "UniswapV3DirectToLiquidity", bytecodeHash);
    }

    function generateBaselineQuoteToken() public {
        // Generate a salt for a MockERC20 quote token
        bytes memory qtArgs = abi.encode("Quote Token", "QT", 18);
        bytes memory qtContractCode = type(MockERC20).creationCode;
        (string memory qtBytecodePath, bytes32 qtBytecodeHash) =
            _writeBytecode("QuoteToken", qtContractCode, qtArgs);
        _setTestSalt(qtBytecodePath, "AA", "QuoteToken", qtBytecodeHash);

        // Fetch the salt that was set
        bytes32 quoteTokenSalt = _getSalt("Test_QuoteToken", qtContractCode, qtArgs);

        // Get the address of the quote token
        // Update the `_BASELINE_QUOTE_TOKEN` constants with this value
        MockERC20 quoteToken = new MockERC20{salt: quoteTokenSalt}("Quote Token", "QT", 18);
        console2.log("Quote Token address: ", address(quoteToken));
    }

    function generateBaselineAxisLaunch() public {
        // Get the salt
        bytes memory callbackArgs =
            abi.encode(_AUCTION_HOUSE, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _OWNER);
        (string memory callbackBytecodePath, bytes32 callbackBytecodeHash) = _writeBytecode(
            "BaselineAxisLaunch", type(BaselineAxisLaunch).creationCode, callbackArgs
        );
        _setTestSalt(callbackBytecodePath, "EF", "BaselineAxisLaunch", callbackBytecodeHash);
    }

    function generateBaselineAllocatedAllowlist() public {
        // Get the salt
        bytes memory callbackArgs =
            abi.encode(_AUCTION_HOUSE, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _OWNER);
        (string memory callbackBytecodePath, bytes32 callbackBytecodeHash) = _writeBytecode(
            "BaselineAllocatedAllowlist", type(BALwithAllocatedAllowlist).creationCode, callbackArgs
        );
        _setTestSalt(callbackBytecodePath, "EF", "BaselineAllocatedAllowlist", callbackBytecodeHash);
    }
}
