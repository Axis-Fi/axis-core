/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";
import {WithSalts} from "script/salts/WithSalts.s.sol";

import {MerkleAllowlist} from "src/callbacks/allowlists/MerkleAllowlist.sol";
import {CappedMerkleAllowlist} from "src/callbacks/allowlists/CappedMerkleAllowlist.sol";
import {TokenAllowlist} from "src/callbacks/allowlists/TokenAllowlist.sol";
import {AllocatedMerkleAllowlist} from "src/callbacks/allowlists/AllocatedMerkleAllowlist.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

contract AllowlistSalts is Script, WithEnvironment, WithSalts {
    string internal constant _ADDRESS_PREFIX = "98";

    address internal _envAtomicAuctionHouse;
    address internal _envBatchAuctionHouse;

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();

        // Cache auction houses
        _envAtomicAuctionHouse = _envAddress("axis.AtomicAuctionHouse");
        console2.log("AtomicAuctionHouse:", _envAtomicAuctionHouse);
        _envBatchAuctionHouse = _envAddress("axis.BatchAuctionHouse");
        console2.log("BatchAuctionHouse:", _envBatchAuctionHouse);
    }

    function generate(string calldata chain_, bool atomic_) public {
        _setUp(chain_);

        address auctionHouse = atomic_ ? _envAtomicAuctionHouse : _envBatchAuctionHouse;

        // All of these allowlists have the same permissions and constructor args
        string memory prefix = "98";
        bytes memory args = abi.encode(
            auctionHouse,
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

        // Merkle Allowlist
        // 10011000 = 0x98
        bytes memory contractCode = type(MerkleAllowlist).creationCode;
        string memory saltKey = "MerkleAllowlist";
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(saltKey, contractCode, args);
        _setSalt(bytecodePath, prefix, saltKey, bytecodeHash);

        // Capped Merkle Allowlist
        // 10011000 = 0x98
        contractCode = type(CappedMerkleAllowlist).creationCode;
        saltKey = "CappedMerkleAllowlist";
        (bytecodePath, bytecodeHash) = _writeBytecode(saltKey, contractCode, args);
        _setSalt(bytecodePath, prefix, saltKey, bytecodeHash);

        // Token Allowlist
        // 10011000 = 0x98
        contractCode = type(TokenAllowlist).creationCode;
        saltKey = "TokenAllowlist";
        (bytecodePath, bytecodeHash) = _writeBytecode(saltKey, contractCode, args);
        _setSalt(bytecodePath, prefix, saltKey, bytecodeHash);

        // Allocated Allowlist
        contractCode = type(AllocatedMerkleAllowlist).creationCode;
        saltKey = "AllocatedMerkleAllowlist";
        (bytecodePath, bytecodeHash) = _writeBytecode(saltKey, contractCode, args);
        _setSalt(bytecodePath, prefix, saltKey, bytecodeHash);
    }
}
