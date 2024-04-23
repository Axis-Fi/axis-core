// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console2} from "forge-std/Script.sol";

// System contracts
import {BlastAtomicAuctionHouse} from "src/blast/BlastAtomicAuctionHouse.sol";
import {BlastBatchAuctionHouse} from "src/blast/BlastBatchAuctionHouse.sol";
import {BlastEMP} from "src/blast/modules/auctions/BlastEMP.sol";
import {BlastFPSale} from "src/blast/modules/auctions/BlastFPS.sol";
import {BlastLinearVesting} from "src/blast/modules/derivatives/BlastLinearVesting.sol";

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

    function _deployAtomicAuctionHouse(bytes32 salt_) internal override returns (address) {
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

        return address(atomicAuctionHouse);
    }

    function _deployBatchAuctionHouse(bytes32 salt_) internal override returns (address) {
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

        return address(batchAuctionHouse);
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function deployEncryptedMarginalPrice(
        bytes memory,
        bytes32 salt_
    ) public override returns (address) {
        // No args used

        console2.log("Deploying EncryptedMarginalPrice");
        console2.log("    BatchAuctionHouse", address(batchAuctionHouse));
        console2.log("    salt:", vm.toString(salt_));

        // Deploy the module
        amEmp = new BlastEMP{salt: salt_}(address(batchAuctionHouse), _envBlast);
        console2.log("    EncryptedMarginalPrice deployed at:", address(amEmp));

        return address(amEmp);
    }

    function deployFixedPriceSale(bytes memory, bytes32 salt_) public override returns (address) {
        // No args used

        console2.log("Deploying FixedPriceSale");
        console2.log("    AtomicAuctionHouse", address(atomicAuctionHouse));
        console2.log("    salt:", vm.toString(salt_));

        // Deploy the module
        amFps = new BlastFPSale{salt: salt_}(address(atomicAuctionHouse), _envBlast);
        console2.log("    FixedPriceSale deployed at:", address(amFps));

        return address(amFps);
    }

    function deployAtomicLinearVesting(
        bytes memory,
        bytes32 salt_
    ) public override returns (address) {
        // No args used

        console2.log("Deploying LinearVesting (Atomic)");
        console2.log("    AtomicAuctionHouse", address(atomicAuctionHouse));
        console2.log("    salt:", vm.toString(salt_));

        // Deploy the module
        dmAtomicLinearVesting =
            new BlastLinearVesting{salt: salt_}(address(atomicAuctionHouse), _envBlast);
        console2.log("    LinearVesting (Atomic) deployed at:", address(dmAtomicLinearVesting));

        return address(dmAtomicLinearVesting);
    }

    function deployBatchLinearVesting(
        bytes memory,
        bytes32 salt_
    ) public override returns (address) {
        // No args used

        console2.log("Deploying LinearVesting (Batch)");
        console2.log("    BatchAuctionHouse", address(batchAuctionHouse));
        console2.log("    salt:", vm.toString(salt_));

        // Deploy the module
        dmBatchLinearVesting =
            new BlastLinearVesting{salt: salt_}(address(batchAuctionHouse), _envBlast);
        console2.log("    LinearVesting (Batch) deployed at:", address(dmBatchLinearVesting));

        return address(dmBatchLinearVesting);
    }
}
