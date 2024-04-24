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

    function _deployAtomicAuctionHouse() internal override returns (address) {
        // No args

        console2.log("Deploying BlastAtomicAuctionHouse");
        console2.log("    owner:", _envOwner);
        console2.log("    permit2:", _envPermit2);
        console2.log("    protocol:", _envProtocol);
        console2.log("    blast:", _envBlast);
        console2.log("    weth:", _envWeth);
        console2.log("    usdb:", _envUsdb);

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BlastAtomicAuctionHouse",
            abi.encode(_envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb)
        );

        if (salt_ == bytes32(0)) {
            vm.broadcast();
            atomicAuctionHouse = new BlastAtomicAuctionHouse(
                _envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb
            );
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            atomicAuctionHouse = new BlastAtomicAuctionHouse{salt: salt_}(
                _envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb
            );
        }
        console2.log("    BlastAtomicAuctionHouse deployed at:", address(atomicAuctionHouse));

        return address(atomicAuctionHouse);
    }

    function _deployBatchAuctionHouse() internal override returns (address) {
        // No args

        console2.log("Deploying BlastBatchAuctionHouse");
        console2.log("    owner:", _envOwner);
        console2.log("    permit2:", _envPermit2);
        console2.log("    protocol:", _envProtocol);
        console2.log("    blast:", _envBlast);
        console2.log("    weth:", _envWeth);
        console2.log("    usdb:", _envUsdb);

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BlastBatchAuctionHouse",
            abi.encode(_envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb)
        );

        if (salt_ == bytes32(0)) {
            vm.broadcast();
            batchAuctionHouse = new BlastBatchAuctionHouse(
                _envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb
            );
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            batchAuctionHouse = new BlastBatchAuctionHouse{salt: salt_}(
                _envOwner, _envProtocol, _envPermit2, _envBlast, _envWeth, _envUsdb
            );
        }
        console2.log("    BlastBatchAuctionHouse deployed at:", address(batchAuctionHouse));

        return address(batchAuctionHouse);
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function deployEncryptedMarginalPrice(bytes memory) public override returns (address) {
        // No args used

        console2.log("Deploying BlastEncryptedMarginalPrice");
        console2.log("    BatchAuctionHouse", address(batchAuctionHouse));
        console2.log("    blast:", _envBlast);

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BlastEncryptedMarginalPrice", abi.encode(address(batchAuctionHouse), _envBlast)
        );

        // Deploy the module
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            amEmp = new BlastEMP(address(batchAuctionHouse), _envBlast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            amEmp = new BlastEMP{salt: salt_}(address(batchAuctionHouse), _envBlast);
        }
        console2.log("    BlastEncryptedMarginalPrice deployed at:", address(amEmp));

        return address(amEmp);
    }

    function deployFixedPriceSale(bytes memory) public override returns (address) {
        // No args used

        console2.log("Deploying BlastFixedPriceSale");
        console2.log("    AtomicAuctionHouse", address(atomicAuctionHouse));
        console2.log("    blast:", _envBlast);

        // Get the salt
        bytes32 salt_ =
            _getSalt("BlastFixedPriceSale", abi.encode(address(atomicAuctionHouse), _envBlast));

        // Deploy the module
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            amFps = new BlastFPSale(address(atomicAuctionHouse), _envBlast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            amFps = new BlastFPSale{salt: salt_}(address(atomicAuctionHouse), _envBlast);
        }
        console2.log("    BlastFixedPriceSale deployed at:", address(amFps));

        return address(amFps);
    }

    function deployAtomicLinearVesting(bytes memory) public override returns (address) {
        // No args used

        console2.log("Deploying BlastLinearVesting (Atomic)");
        console2.log("    AtomicAuctionHouse", address(atomicAuctionHouse));
        console2.log("    blast:", _envBlast);

        // Get the salt
        bytes32 salt_ =
            _getSalt("BlastLinearVesting", abi.encode(address(atomicAuctionHouse), _envBlast));

        // Deploy the module
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            dmAtomicLinearVesting = new BlastLinearVesting(address(atomicAuctionHouse), _envBlast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            dmAtomicLinearVesting =
                new BlastLinearVesting{salt: salt_}(address(atomicAuctionHouse), _envBlast);
        }
        console2.log("    LinearVesting (Atomic) deployed at:", address(dmAtomicLinearVesting));

        return address(dmAtomicLinearVesting);
    }

    function deployBatchLinearVesting(bytes memory) public override returns (address) {
        // No args used

        console2.log("Deploying LinearVesting (Batch)");
        console2.log("    BatchAuctionHouse", address(batchAuctionHouse));
        console2.log("    blast:", _envBlast);

        // Get the salt
        bytes32 salt_ =
            _getSalt("BlastLinearVesting", abi.encode(address(batchAuctionHouse), _envBlast));

        // Deploy the module
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            dmBatchLinearVesting = new BlastLinearVesting(address(batchAuctionHouse), _envBlast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            dmBatchLinearVesting =
                new BlastLinearVesting{salt: salt_}(address(batchAuctionHouse), _envBlast);
        }
        console2.log("    LinearVesting (Batch) deployed at:", address(dmBatchLinearVesting));

        return address(dmBatchLinearVesting);
    }
}
