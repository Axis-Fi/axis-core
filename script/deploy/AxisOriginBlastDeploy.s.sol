// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";

// System contracts
import {BlastAtomicAuctionHouse} from "src/blast/BlastAtomicAuctionHouse.sol";
import {BlastBatchAuctionHouse} from "src/blast/BlastBatchAuctionHouse.sol";
import {AtomicCatalogue} from "src/AtomicCatalogue.sol";
import {BatchCatalogue} from "src/BatchCatalogue.sol";
import {BlastEMP} from "src/blast/modules/auctions/BlastEMP.sol";
import {BlastFPSale} from "src/blast/modules/auctions/BlastFPS.sol";
import {BlastLinearVesting} from "src/blast/modules/derivatives/BlastLinearVesting.sol";

contract AxisOriginDeploy is Script {
    BlastAtomicAuctionHouse public atomicAuctionHouse;
    BlastBatchAuctionHouse public batchAuctionHouse;
    AtomicCatalogue public atomicCatalogue;
    BatchCatalogue public batchCatalogue;
    BlastEMP public emp;
    BlastFPSale public fps;
    BlastLinearVesting public linearVestingA;
    BlastLinearVesting public linearVestingB;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public blast;
    address public weth;
    address public usdb;

    function deploy() public {
        // Load the protocol address to receive fees at
        address protocol = vm.envAddress("PROTOCOL");

        vm.startBroadcast();

        // Assume permit2 is already deployed at canonical address

        // // Calculate salt for the atomic auction house
        // bytes memory bytecode = abi.encodePacked(
        //     type(BlastAtomicAuctionHouse).creationCode, abi.encode(msg.sender, protocol, PERMIT2)
        // );
        // vm.writeFile("./bytecode/BlastAtomicAuctionHouse.bin", vm.toString(bytecode));
        // bytecode = abi.encodePacked(
        //     type(BlastBatchAuctionHouse).creationCode, abi.encode(msg.sender, protocol, PERMIT2)
        // );
        // vm.writeFile("./bytecode/BlastBatchAuctionHouse.bin", vm.toString(bytecode));

        // TODO set blast, weth, usdb

        // Load salt for Auction House
        bytes32 atomicSalt = vm.envBytes32("BLAST_ATOMIC_AUCTION_HOUSE_SALT");
        bytes32 batchSalt = vm.envBytes32("BLAST_BATCH_AUCTION_HOUSE_SALT");

        atomicAuctionHouse = new BlastAtomicAuctionHouse{salt: atomicSalt}(
            msg.sender, protocol, PERMIT2, blast, weth, usdb
        );
        console2.log("BlastAtomicAuctionHouse deployed at: ", address(atomicAuctionHouse));
        batchAuctionHouse = new BlastBatchAuctionHouse{salt: batchSalt}(
            msg.sender, protocol, PERMIT2, blast, weth, usdb
        );
        console2.log("BlastBatchAuctionHouse deployed at: ", address(batchAuctionHouse));

        atomicCatalogue = new AtomicCatalogue(address(atomicAuctionHouse));
        console2.log("AtomicCatalogue deployed at: ", address(atomicCatalogue));
        batchCatalogue = new BatchCatalogue(address(batchAuctionHouse));
        console2.log("BatchCatalogue deployed at: ", address(batchCatalogue));

        emp = new BlastEMP(address(batchAuctionHouse), blast);
        console2.log("BlastEMP deployed at: ", address(emp));

        batchAuctionHouse.installModule(emp);
        console2.log("BlastEMP installed at BatchAuctionHouse");

        fps = new BlastFPSale(address(atomicAuctionHouse), blast);
        console2.log("BlastFPSale deployed at: ", address(fps));

        atomicAuctionHouse.installModule(fps);
        console2.log("BlastFPSale installed at AtomicAuctionHouse");

        // Linear vesting A
        linearVestingA = new BlastLinearVesting(address(atomicAuctionHouse), blast);
        console2.log("BlastLinearVesting A deployed at: ", address(linearVestingA));

        atomicAuctionHouse.installModule(linearVestingA);
        console2.log("BlastLinearVesting A installed at AtomicAuctionHouse");

        // Linear vesting B
        linearVestingB = new BlastLinearVesting(address(batchAuctionHouse), blast);
        console2.log("BlastLinearVesting A deployed at: ", address(linearVestingB));

        batchAuctionHouse.installModule(linearVestingB);
        console2.log("BlastLinearVesting B installed at BatchAuctionHouse");

        vm.stopBroadcast();
    }
}