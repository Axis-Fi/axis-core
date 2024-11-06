// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console2} from "@forge-std-1.9.1/Script.sol";

// System contracts
import {BlastAtomicAuctionHouse} from "../../src/blast/BlastAtomicAuctionHouse.sol";
import {BlastBatchAuctionHouse} from "../../src/blast/BlastBatchAuctionHouse.sol";
import {BlastEMP} from "../../src/blast/modules/auctions/batch/BlastEMP.sol";
import {BlastFPS} from "../../src/blast/modules/auctions/atomic/BlastFPS.sol";
import {BlastFPB} from "../../src/blast/modules/auctions/batch/BlastFPB.sol";
import {BlastLinearVesting} from "../../src/blast/modules/derivatives/BlastLinearVesting.sol";

import {Deploy} from "./Deploy.s.sol";

/// @notice Declarative deploy script that uses contracts specific to the Blast L2 chain.
///         See Deploy.s.sol for more information on the Deploy contract.
contract DeployBlast is Deploy {
    // ========== AUCTIONHOUSE DEPLOYMENTS ========== //

    function _deployAtomicAuctionHouse() internal override returns (address) {
        // No args
        console2.log("");
        console2.log("Deploying BlastAtomicAuctionHouse");

        address owner = _getAddressNotZero("constants.axis.OWNER");
        address protocol = _getAddressNotZero("constants.axis.PROTOCOL");
        address permit2 = _getAddressNotZero("constants.axis.PERMIT2");
        address blast = _getAddressNotZero("constants.blast.blast");
        address blastWeth = _getAddressNotZero("constants.blast.weth");
        address blastUsdb = _getAddressNotZero("constants.blast.usdb");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BlastAtomicAuctionHouse",
            type(BlastAtomicAuctionHouse).creationCode,
            abi.encode(owner, protocol, permit2, blast, blastWeth, blastUsdb)
        );

        BlastAtomicAuctionHouse atomicAuctionHouse;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            atomicAuctionHouse =
                new BlastAtomicAuctionHouse(owner, protocol, permit2, blast, blastWeth, blastUsdb);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            atomicAuctionHouse = new BlastAtomicAuctionHouse{salt: salt_}(
                owner, protocol, permit2, blast, blastWeth, blastUsdb
            );
        }
        console2.log("    BlastAtomicAuctionHouse deployed at:", address(atomicAuctionHouse));

        return address(atomicAuctionHouse);
    }

    function _deployBatchAuctionHouse() internal override returns (address) {
        // No args
        console2.log("");
        console2.log("Deploying BlastBatchAuctionHouse");

        address owner = _getAddressNotZero("constants.axis.OWNER");
        address protocol = _getAddressNotZero("constants.axis.PROTOCOL");
        address permit2 = _getAddressNotZero("constants.axis.PERMIT2");
        address blast = _getAddressNotZero("constants.blast.blast");
        address blastWeth = _getAddressNotZero("constants.blast.weth");
        address blastUsdb = _getAddressNotZero("constants.blast.usdb");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BlastBatchAuctionHouse",
            type(BlastBatchAuctionHouse).creationCode,
            abi.encode(owner, protocol, permit2, blast, blastWeth, blastUsdb)
        );

        BlastBatchAuctionHouse batchAuctionHouse;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            batchAuctionHouse =
                new BlastBatchAuctionHouse(owner, protocol, permit2, blast, blastWeth, blastUsdb);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            batchAuctionHouse = new BlastBatchAuctionHouse{salt: salt_}(
                owner, protocol, permit2, blast, blastWeth, blastUsdb
            );
        }
        console2.log("    BlastBatchAuctionHouse deployed at:", address(batchAuctionHouse));

        return address(batchAuctionHouse);
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function deployEncryptedMarginalPrice(
        bytes memory
    ) public override returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying BlastEMP (Encrypted Marginal Price)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address blast = _getAddressNotZero("constants.blast.blast");

        // Get the salt
        bytes32 salt_ =
            _getSalt("BlastEMP", type(BlastEMP).creationCode, abi.encode(batchAuctionHouse, blast));

        // Deploy the module
        BlastEMP amEmp;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            amEmp = new BlastEMP(batchAuctionHouse, blast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            amEmp = new BlastEMP{salt: salt_}(batchAuctionHouse, blast);
        }
        console2.log("    BlastEMP deployed at:", address(amEmp));

        return (address(amEmp), _PREFIX_AUCTION_MODULES);
    }

    function deployFixedPriceSale(
        bytes memory
    ) public override returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying BlastFPS (Fixed Price Sale)");

        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        address blast = _getAddressNotZero("constants.blast.blast");

        // Get the salt
        bytes32 salt_ =
            _getSalt("BlastFPS", type(BlastFPS).creationCode, abi.encode(atomicAuctionHouse, blast));

        // Deploy the module
        BlastFPS amFps;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            amFps = new BlastFPS(atomicAuctionHouse, blast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            amFps = new BlastFPS{salt: salt_}(atomicAuctionHouse, blast);
        }
        console2.log("    BlastFPS deployed at:", address(amFps));

        return (address(amFps), _PREFIX_AUCTION_MODULES);
    }

    function deployFixedPriceBatch(
        bytes memory
    ) public override returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying BlastFPB (Fixed Price Batch)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address blast = _getAddressNotZero("constants.blast.blast");

        // Get the salt
        bytes32 salt_ =
            _getSalt("BlastFPB", type(BlastFPB).creationCode, abi.encode(batchAuctionHouse, blast));

        // Deploy the module
        BlastFPB amFpb;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            amFpb = new BlastFPB(batchAuctionHouse, blast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            amFpb = new BlastFPB{salt: salt_}(batchAuctionHouse, blast);
        }
        console2.log("    BlastFPB deployed at:", address(amFpb));

        return (address(amFpb), _PREFIX_AUCTION_MODULES);
    }

    function deployAtomicLinearVesting(
        bytes memory
    ) public override returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying BlastLinearVesting (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        address blast = _getAddressNotZero("constants.blast.blast");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BlastLinearVesting",
            type(BlastLinearVesting).creationCode,
            abi.encode(atomicAuctionHouse, blast)
        );

        // Deploy the module
        BlastLinearVesting dmAtomicLinearVesting;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            dmAtomicLinearVesting = new BlastLinearVesting(atomicAuctionHouse, blast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            dmAtomicLinearVesting = new BlastLinearVesting{salt: salt_}(atomicAuctionHouse, blast);
        }
        console2.log("    LinearVesting (Atomic) deployed at:", address(dmAtomicLinearVesting));

        return (address(dmAtomicLinearVesting), _PREFIX_DERIVATIVE_MODULES);
    }

    function deployBatchLinearVesting(
        bytes memory
    ) public override returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying LinearVesting (Batch)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address blast = _getAddressNotZero("constants.blast.blast");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BlastLinearVesting",
            type(BlastLinearVesting).creationCode,
            abi.encode(batchAuctionHouse, blast)
        );

        // Deploy the module
        BlastLinearVesting dmBatchLinearVesting;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            dmBatchLinearVesting = new BlastLinearVesting(batchAuctionHouse, blast);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            dmBatchLinearVesting = new BlastLinearVesting{salt: salt_}(batchAuctionHouse, blast);
        }
        console2.log("    LinearVesting (Batch) deployed at:", address(dmBatchLinearVesting));

        return (address(dmBatchLinearVesting), _PREFIX_DERIVATIVE_MODULES);
    }
}
