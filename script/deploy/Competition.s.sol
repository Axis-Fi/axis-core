/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";

// System contracts
import {AuctionHouse} from "src/AuctionHouse.sol";
import {LocalSealedBidBatchAuction} from "src/modules/auctions/LSBBA/LSBBA.sol";

contract CompetitionDeploy is Script {

    AuctionHouse public auctionHouse;
    LocalSealedBidBatchAuction public lsbba;

    function deploy() public {
        vm.startBroadcast();
        
        auctionHouse = new AuctionHouse(msg.sender, address(0));
        console2.log("AuctionHouse deployed at: ", address(auctionHouse));

        lsbba = new LocalSealedBidBatchAuction(address(auctionHouse));
        console2.log("LocalSealedBidBatchAuction deployed at: ", address(lsbba));

        vm.stopBroadcast();
    }
}