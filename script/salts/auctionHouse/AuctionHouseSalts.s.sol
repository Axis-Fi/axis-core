/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithEnvironment} from "../../deploy/WithEnvironment.s.sol";
import {WithSalts} from "../WithSalts.s.sol";

import {AtomicAuctionHouse} from "../../../src/AtomicAuctionHouse.sol";
import {BatchAuctionHouse} from "../../../src/BatchAuctionHouse.sol";

contract AuctionHouseSalts is Script, WithEnvironment, WithSalts {
    address internal _envOwner;
    address internal _envPermit2;
    address internal _envProtocol;

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();

        // Cache required variables
        _envOwner = _envAddressNotZero("constants.axis.OWNER");
        console2.log("Owner:", _envOwner);
        _envPermit2 = _envAddressNotZero("constants.axis.PERMIT2");
        console2.log("Permit2:", _envPermit2);
        _envProtocol = _envAddressNotZero("constants.axis.PROTOCOL");
        console2.log("Protocol:", _envProtocol);
    }

    function generate(string calldata chain_, string calldata prefix_, bool atomic_) public {
        _setUp(chain_);

        bytes memory args = abi.encode(_envOwner, _envProtocol, _envPermit2);

        if (atomic_) {
            // Calculate salt for the AtomicAuctionHouse
            bytes memory contractCode = type(AtomicAuctionHouse).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) =
                _writeBytecode("AtomicAuctionHouse", contractCode, args);
            _setSalt(bytecodePath, prefix_, "AtomicAuctionHouse", bytecodeHash);
        } else {
            // Calculate salt for the BatchAuctionHouse
            bytes memory contractCode = type(BatchAuctionHouse).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) =
                _writeBytecode("BatchAuctionHouse", contractCode, args);
            _setSalt(bytecodePath, prefix_, "BatchAuctionHouse", bytecodeHash);
        }
    }
}
