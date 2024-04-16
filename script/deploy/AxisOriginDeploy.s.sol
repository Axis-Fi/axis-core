/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";

// System contracts
import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {AtomicCatalogue} from "src/AtomicCatalogue.sol";
import {BatchCatalogue} from "src/BatchCatalogue.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/EMP.sol";
import {FixedPriceSale} from "src/modules/auctions/FPS.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

contract AxisOriginDeploy is Script {
    AtomicAuctionHouse public atomicAuctionHouse;
    BatchAuctionHouse public batchAuctionHouse;
    AtomicCatalogue public atomicCatalogue;
    BatchCatalogue public batchCatalogue;
    EncryptedMarginalPrice public emp;
    FixedPriceSale public fps;
    LinearVesting public atomicLinearVesting;
    LinearVesting public batchLinearVesting;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function deploy() public {
        // Load the protocol address to receive fees at
        address protocol = vm.envAddress("PROTOCOL");

        vm.startBroadcast();

        // Assume permit2 is already deployed at canonical address

        // // Calculate salt for the atomic auction house
        // bytes memory bytecode = abi.encodePacked(
        //     type(AtomicAuctionHouse).creationCode, abi.encode(msg.sender, protocol, PERMIT2)
        // );
        // vm.writeFile("./bytecode/AtomicAuctionHouse.bin", vm.toString(bytecode));
        // bytecode = abi.encodePacked(
        //     type(BatchAuctionHouse).creationCode, abi.encode(msg.sender, protocol, PERMIT2)
        // );
        // vm.writeFile("./bytecode/BatchAuctionHouse.bin", vm.toString(bytecode));

        // Load salt for Auction House
        bytes32 atomicSalt = vm.envBytes32("ATOMIC_AUCTION_HOUSE_SALT");
        bytes32 batchSalt = vm.envBytes32("BATCH_AUCTION_HOUSE_SALT");

        atomicAuctionHouse = new AtomicAuctionHouse{salt: atomicSalt}(msg.sender, protocol, PERMIT2);
        console2.log("AtomicAuctionHouse deployed at: ", address(atomicAuctionHouse));
        batchAuctionHouse = new BatchAuctionHouse{salt: batchSalt}(msg.sender, protocol, PERMIT2);
        console2.log("BatchAuctionHouse deployed at: ", address(batchAuctionHouse));

        atomicCatalogue = new AtomicCatalogue(address(atomicAuctionHouse));
        console2.log("AtomicCatalogue deployed at: ", address(atomicCatalogue));
        batchCatalogue = new BatchCatalogue(address(batchAuctionHouse));
        console2.log("BatchCatalogue deployed at: ", address(batchCatalogue));

        emp = new EncryptedMarginalPrice(address(batchAuctionHouse));
        console2.log("EMP deployed at: ", address(emp));
        batchAuctionHouse.installModule(emp);
        console2.log("EMP installed at BatchAuctionHouse");

        fps = new FixedPriceSale(address(atomicAuctionHouse));
        console2.log("FPSale deployed at: ", address(fps));
        atomicAuctionHouse.installModule(fps);
        console2.log("FPSale installed at AtomicAuctionHouse");

        atomicLinearVesting = new LinearVesting(address(atomicAuctionHouse));
        console2.log("LinearVesting (Atomic) deployed at: ", address(atomicLinearVesting));
        atomicAuctionHouse.installModule(atomicLinearVesting);
        console2.log("LinearVesting (Atomic) installed at AtomicAuctionHouse");

        batchLinearVesting = new LinearVesting(address(batchAuctionHouse));
        console2.log("LinearVesting (Batch) deployed at: ", address(batchLinearVesting));
        batchAuctionHouse.installModule(batchLinearVesting);
        console2.log("LinearVesting (Batch) installed at BatchAuctionHouse");

        vm.stopBroadcast();
    }
}
