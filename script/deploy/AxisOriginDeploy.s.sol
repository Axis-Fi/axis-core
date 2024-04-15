/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";

// System contracts
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Catalogue} from "src/Catalogue.sol";
import {EncryptedMarginalPriceAuctionModule as EMPAM} from "src/modules/auctions/EMPAM.sol";
import {FixedPriceAuctionModule as FPAM} from "src/modules/auctions/FPAM.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

contract AxisOriginDeploy is Script {
    AuctionHouse public auctionHouse;
    Catalogue public catalogue;
    EMPAM public empam;
    FPAM public fpam;
    LinearVesting public linearVesting;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function deploy() public {
        // Load the protocol address to receive fees at
        address protocol = vm.envAddress("PROTOCOL");

        vm.startBroadcast();

        // Assume permit2 is already deployed at canonical address

        // // Calculate salt for the auction house
        // bytes memory bytecode = abi.encodePacked(
        //     type(AuctionHouse).creationCode, abi.encode(msg.sender, protocol, PERMIT2)
        // );
        // vm.writeFile("./bytecode/AuctionHouse.bin", vm.toString(bytecode));

        // Load salt for Auction House
        bytes32 salt = vm.envBytes32("AUCTION_HOUSE_SALT");

        auctionHouse = new AuctionHouse{salt: salt}(msg.sender, protocol, PERMIT2);
        console2.log("AuctionHouse deployed at: ", address(auctionHouse));

        catalogue = new Catalogue(address(auctionHouse));
        console2.log("Catalogue deployed at: ", address(catalogue));

        empam = new EMPAM(address(auctionHouse));
        console2.log("EMPAM deployed at: ", address(empam));

        fpam = new FPAM(address(auctionHouse));
        console2.log("FPAM deployed at: ", address(fpam));

        linearVesting = new LinearVesting(address(auctionHouse));
        console2.log("LinearVesting deployed at: ", address(linearVesting));

        auctionHouse.installModule(empam);
        console2.log("EMPAM installed at AuctionHouse");

        auctionHouse.installModule(fpam);
        console2.log("FPAM installed at AuctionHouse");

        auctionHouse.installModule(linearVesting);
        console2.log("LinearVesting installed at AuctionHouse");

        vm.stopBroadcast();
    }
}
