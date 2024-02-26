/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";

// System contracts
import {BlastAuctionHouse} from "src/blast/BlastAuctionHouse.sol";
import {Catalogue} from "src/Catalogue.sol";
import {BlastEMPAM} from "src/blast/modules/auctions/BlastEMPAM.sol";
import {BlastLinearVesting} from "src/blast/modules/derivatives/BlastLinearVesting.sol";

contract AxisOriginDeploy is Script {
    BlastAuctionHouse public auctionHouse;
    Catalogue public catalogue;
    BlastEMPAM public empam;
    BlastLinearVesting public linearVesting;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function deploy() public {
        // Load the protocol address to receive fees at
        address protocol = vm.envAddress("PROTOCOL");

        vm.startBroadcast();

        // Assume permit2 is already deployed at canonical address

        // // Calculate salt for the auction house
        // bytes memory bytecode = abi.encodePacked(
        //     type(BlastAuctionHouse).creationCode,
        //     abi.encode(msg.sender, protocol, PERMIT2)
        // );
        // vm.writeFile(
        //     "./bytecode/BlastAuctionHouse.bin",
        //     vm.toString(bytecode)
        // );

        // Load salt for Auction House
        bytes32 salt = vm.envBytes32("AUCTION_HOUSE_SALT");

        auctionHouse = new BlastAuctionHouse{salt: salt}(msg.sender, protocol, PERMIT2);
        console2.log("BlastAuctionHouse deployed at: ", address(auctionHouse));

        catalogue = new Catalogue(address(auctionHouse));
        console2.log("Catalogue deployed at: ", address(catalogue));

        empam = new BlastEMPAM(address(auctionHouse));
        console2.log("BlastEMPAM deployed at: ", address(empam));

        auctionHouse.installModule(empam);
        console2.log("BlastEMPAM installed at AuctionHouse");

        linearVesting = new BlastLinearVesting(address(auctionHouse));
        console2.log("BlastLinearVesting deployed at: ", address(linearVesting));

        auctionHouse.installModule(linearVesting);
        console2.log("BlastLinearVesting installed at AuctionHouse");

        vm.stopBroadcast();
    }
}
