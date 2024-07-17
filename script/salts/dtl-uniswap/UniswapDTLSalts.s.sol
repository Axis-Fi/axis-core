/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";
import {WithSalts} from "script/salts/WithSalts.s.sol";

import {UniswapV2DirectToLiquidity} from "src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";

contract UniswapDTLSalts is Script, WithEnvironment, WithSalts {
    string internal constant _ADDRESS_PREFIX = "E6";

    address internal _envUniswapV2Factory;
    address internal _envUniswapV2Router;
    address internal _envUniswapV3Factory;
    address internal _envGUniFactory;

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();

        // Cache Uniswap factories
        _envUniswapV2Factory = _envAddressNotZero("constants.uniswapV2.factory");
        console2.log("UniswapV2Factory:", _envUniswapV2Factory);
        _envUniswapV2Router = _envAddressNotZero("constants.uniswapV2.router");
        console2.log("UniswapV2Router:", _envUniswapV2Router);
        _envUniswapV3Factory = _envAddressNotZero("constants.uniswapV3.factory");
        console2.log("UniswapV3Factory:", _envUniswapV3Factory);
        _envGUniFactory = _envAddressNotZero("constants.gUni.factory");
        console2.log("GUniFactory:", _envGUniFactory);
    }

    function generate(
        string calldata chain_,
        string calldata uniswapVersion_,
        bool atomic_
    ) public {
        _setUp(chain_);

        if (keccak256(abi.encodePacked(uniswapVersion_)) == keccak256(abi.encodePacked("2"))) {
            _generateV2(atomic_);
        } else if (keccak256(abi.encodePacked(uniswapVersion_)) == keccak256(abi.encodePacked("3")))
        {
            _generateV3(atomic_);
        } else {
            revert("Invalid Uniswap version: 2 or 3");
        }
    }

    function _generateV2(bool atomic_) internal {
        if (atomic_) {
            address _envAtomicAuctionHouse = _envAddressNotZero("deployments.AtomicAuctionHouse");
            console2.log("AtomicAuctionHouse:", _envAtomicAuctionHouse);

            // Calculate salt for the UniswapV2DirectToLiquidity
            bytes memory contractCode = type(UniswapV2DirectToLiquidity).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
                "UniswapV2DirectToLiquidity",
                contractCode,
                abi.encode(_envAtomicAuctionHouse, _envUniswapV2Factory, _envUniswapV2Router)
            );
            _setSalt(bytecodePath, _ADDRESS_PREFIX, "UniswapV2DirectToLiquidity", bytecodeHash);
        } else {
            address _envBatchAuctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");
            console2.log("BatchAuctionHouse:", _envBatchAuctionHouse);

            // Calculate salt for the UniswapV2DirectToLiquidity
            bytes memory contractCode = type(UniswapV2DirectToLiquidity).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
                "UniswapV2DirectToLiquidity",
                contractCode,
                abi.encode(_envBatchAuctionHouse, _envUniswapV2Factory, _envUniswapV2Router)
            );
            _setSalt(bytecodePath, _ADDRESS_PREFIX, "UniswapV2DirectToLiquidity", bytecodeHash);
        }
    }

    function _generateV3(bool atomic_) internal {
        if (atomic_) {
            address _envAtomicAuctionHouse = _envAddressNotZero("deployments.AtomicAuctionHouse");
            console2.log("AtomicAuctionHouse:", _envAtomicAuctionHouse);

            // Calculate salt for the UniswapV3DirectToLiquidity
            bytes memory contractCode = type(UniswapV3DirectToLiquidity).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
                "UniswapV3DirectToLiquidity",
                contractCode,
                abi.encode(_envAtomicAuctionHouse, _envUniswapV3Factory, _envGUniFactory)
            );
            _setSalt(bytecodePath, _ADDRESS_PREFIX, "UniswapV3DirectToLiquidity", bytecodeHash);
        } else {
            address _envBatchAuctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");
            console2.log("BatchAuctionHouse:", _envBatchAuctionHouse);

            // Calculate salt for the UniswapV3DirectToLiquidity
            bytes memory contractCode = type(UniswapV3DirectToLiquidity).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
                "UniswapV3DirectToLiquidity",
                contractCode,
                abi.encode(_envBatchAuctionHouse, _envUniswapV3Factory, _envGUniFactory)
            );
            _setSalt(bytecodePath, _ADDRESS_PREFIX, "UniswapV3DirectToLiquidity", bytecodeHash);
        }
    }
}
