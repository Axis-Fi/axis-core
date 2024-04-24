/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";
import {WithSalts} from "script/salts/WithSalts.s.sol";

import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";

contract AuctionHouseSalts is Script, WithEnvironment, WithSalts {
    address internal _envOwner;
    address internal _envPermit2;
    address internal _envProtocol;

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();

        // Cache required variables
        _envOwner = _envAddress("OWNER");
        console2.log("Owner:", _envOwner);
        _envPermit2 = _envAddress("PERMIT2");
        console2.log("Permit2:", _envPermit2);
        _envProtocol = _envAddress("PROTOCOL");
        console2.log("Protocol:", _envProtocol);
    }

    function generate(string calldata chain_, string calldata prefix_) public {
        _setUp(chain_);

        // Calculate salt for the AtomicAuctionHouse
        bytes memory args = abi.encode(_envOwner, _envProtocol, _envPermit2);
        bytes memory contractCode = type(AtomicAuctionHouse).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("AtomicAuctionHouse", contractCode, args);
        _setSalt(bytecodePath, prefix_, "AtomicAuctionHouse", bytecodeHash);

        // Calculate salt for the BatchAuctionHouse
        contractCode = type(BatchAuctionHouse).creationCode;
        (bytecodePath, bytecodeHash) = _writeBytecode("BatchAuctionHouse", contractCode, args);
        _setSalt(bytecodePath, prefix_, "BatchAuctionHouse", bytecodeHash);
    }
}
