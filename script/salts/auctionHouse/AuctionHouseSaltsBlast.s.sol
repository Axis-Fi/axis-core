/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithEnvironment} from "../../deploy/WithEnvironment.s.sol";
import {WithSalts} from "../WithSalts.s.sol";

import {BlastAtomicAuctionHouse} from "../../../src/blast/BlastAtomicAuctionHouse.sol";
import {BlastBatchAuctionHouse} from "../../../src/blast/BlastBatchAuctionHouse.sol";

contract AuctionHouseSaltsBlast is Script, WithEnvironment, WithSalts {
    address internal _envOwner;
    address internal _envPermit2;
    address internal _envProtocol;
    address internal _envBlast;
    address internal _envWeth;
    address internal _envUsdb;

    function _setUp(
        string calldata chain_
    ) internal {
        _loadEnv(chain_);

        // Cache required variables
        _envOwner = _envAddressNotZero("constants.axis.OWNER");
        console2.log("Owner:", _envOwner);
        _envPermit2 = _envAddressNotZero("constants.axis.PERMIT2");
        console2.log("Permit2:", _envPermit2);
        _envProtocol = _envAddressNotZero("constants.axis.PROTOCOL");
        console2.log("Protocol:", _envProtocol);
        _envBlast = _envAddressNotZero("constants.blast.blast");
        console2.log("Blast:", _envBlast);
        _envWeth = _envAddressNotZero("constants.blast.weth");
        console2.log("WETH:", _envWeth);
        _envUsdb = _envAddressNotZero("constants.blast.usdb");
        console2.log("USDB:", _envUsdb);
    }

    function generate(string calldata chain_, string calldata prefix_, bool atomic_) public {
        _setUp(chain_);

        // Calculate salt for the BlastAtomicAuctionHouse
        bytes memory args =
            abi.encode(_envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb);

        if (atomic_) {
            bytes memory contractCode = type(BlastAtomicAuctionHouse).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) =
                _writeBytecode("BlastAtomicAuctionHouse", contractCode, args);
            _setSalt(bytecodePath, prefix_, "BlastAtomicAuctionHouse", bytecodeHash);
        } else {
            // Calculate salt for the BlastBatchAuctionHouse
            bytes memory contractCode = type(BlastBatchAuctionHouse).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) =
                _writeBytecode("BlastBatchAuctionHouse", contractCode, args);
            _setSalt(bytecodePath, prefix_, "BlastBatchAuctionHouse", bytecodeHash);
        }
    }
}
