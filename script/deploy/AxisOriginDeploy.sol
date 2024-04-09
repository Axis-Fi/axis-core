/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";

// System contracts
import {BlastAtomicAuctionHouse} from "src/blast/BlastAtomicAuctionHouse.sol";
import {BlastBatchAuctionHouse} from "src/blast/BlastBatchAuctionHouse.sol";
import {AtomicCatalogue} from "src/AtomicCatalogue.sol";
import {BlastEMPAM} from "src/blast/modules/auctions/BlastEMPAM.sol";
import {BlastLinearVesting} from "src/blast/modules/derivatives/BlastLinearVesting.sol";

contract AxisOriginDeploy is Script {
    BlastAtomicAuctionHouse public atomicAuctionHouse;
    BlastBatchAuctionHouse public batchAuctionHouse;
    AtomicCatalogue public atomicCatalogue;
    // BlastFPAM public fpam;
    BlastEMPAM public empam;
    BlastLinearVesting public linearVesting;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function deploy() public {
        // Load the protocol address to receive fees at
        address protocol = vm.envAddress("PROTOCOL");

        vm.startBroadcast();

        // Assume permit2 is already deployed at canonical address

        // // Calculate salt for the atomic auction house
        // bytes memory bytecode = abi.encodePacked(
        //     type(BlastAtomicAuctionHouse).creationCode,
        //     abi.encode(msg.sender, protocol, PERMIT2)
        // );
        // vm.writeFile(
        //     "./bytecode/BlastAtomicAuctionHouse.bin",
        //     vm.toString(bytecode)
        // );
        // bytecode = abi.encodePacked(
        //     type(BlastBatchAuctionHouse).creationCode,
        //     abi.encode(msg.sender, protocol, PERMIT2)
        // );
        // vm.writeFile(
        //     "./bytecode/BlastBatchAuctionHouse.bin",
        //     vm.toString(bytecode)
        // );

        // Load salt for Auction House
        bytes32 atomicSalt = vm.envBytes32("ATOMIC_AUCTION_HOUSE_SALT");
        bytes32 batchSalt = vm.envBytes32("BATCH_AUCTION_HOUSE_SALT");

        atomicAuctionHouse = new BlastAtomicAuctionHouse{salt: atomicSalt}(msg.sender, protocol, PERMIT2);
        console2.log("BlastAtomicAuctionHouse deployed at: ", address(atomicAuctionHouse));
        batchAuctionHouse = new BlastBatchAuctionHouse{salt: batchSalt}(msg.sender, protocol, PERMIT2);
        console2.log("BlastBatchAuctionHouse deployed at: ", address(batchAuctionHouse));

        atomicCatalogue = new AtomicCatalogue(address(atomicAuctionHouse));
        console2.log("Catalogue deployed at: ", address(atomicCatalogue));

        empam = new BlastEMPAM(address(batchAuctionHouse));
        console2.log("BlastEMPAM deployed at: ", address(empam));

        batchAuctionHouse.installModule(empam);
        console2.log("BlastEMPAM installed at BatchAuctionHouse");

        // TODO FPA

        // Linear vesting
        linearVesting = new BlastLinearVesting(address(batchAuctionHouse));
        console2.log("BlastLinearVesting deployed at: ", address(linearVesting));

        batchAuctionHouse.installModule(linearVesting);
        console2.log("BlastLinearVesting installed at BatchAuctionHouse");
        atomicAuctionHouse.installModule(linearVesting);
        console2.log("BlastLinearVesting installed at AtomicAuctionHouse");

        vm.stopBroadcast();
    }
}
