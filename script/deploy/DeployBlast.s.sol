// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console2} from "forge-std/Script.sol";

// System contracts
import {BlastAtomicAuctionHouse} from "src/blast/BlastAtomicAuctionHouse.sol";
import {BlastBatchAuctionHouse} from "src/blast/BlastBatchAuctionHouse.sol";

import {Deploy} from "script/deploy/Deploy.s.sol";

contract DeployBlast is Deploy {
    // Blast-specific environment variables
    address internal _envBlast;
    address internal _envWeth;
    address internal _envUsdb;

    function _setUp(string calldata chain_, string calldata deployFilePath_) internal override {
        super._setUp(chain_, deployFilePath_);

        // Cache required variables
        _envBlast = _envAddress("BLAST");
        console2.log("Blast:", _envBlast);
        _envWeth = _envAddress("BLAST_WETH");
        console2.log("WETH:", _envWeth);
        _envUsdb = _envAddress("BLAST_USDB");
        console2.log("USDB:", _envUsdb);
    }

    // ========== AUCTIONHOUSE DEPLOYMENTS ========== //

    function _deployAtomicAuctionHouse(bytes32 salt_) internal override {
        // No args

        console2.log("Deploying BlastAtomicAuctionHouse");
        console2.log("    owner:", _envOwner);
        console2.log("    permit2:", _envPermit2);
        console2.log("    protocol:", _envProtocol);
        console2.log("    blast:", _envBlast);
        console2.log("    weth:", _envWeth);
        console2.log("    usdb:", _envUsdb);
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        atomicAuctionHouse = new BlastAtomicAuctionHouse{salt: salt_}(
            _envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb
        );
        console2.log("    BlastAtomicAuctionHouse deployed at:", address(atomicAuctionHouse));
    }

    function _deployBatchAuctionHouse(bytes32 salt_) internal override {
        // No args

        console2.log("Deploying BlastBatchAuctionHouse");
        console2.log("    owner:", _envOwner);
        console2.log("    permit2:", _envPermit2);
        console2.log("    protocol:", _envProtocol);
        console2.log("    blast:", _envBlast);
        console2.log("    weth:", _envWeth);
        console2.log("    usdb:", _envUsdb);
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        batchAuctionHouse = new BlastBatchAuctionHouse{salt: salt_}(
            _envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb
        );
        console2.log("    BlastBatchAuctionHouse deployed at:", address(batchAuctionHouse));
    }
}
