/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";

// Test contracts
import {Permit2Clone} from "test/lib/permit2/Permit2Clone.sol";

// System contracts
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Catalogue} from "src/Catalogue.sol";
import {LocalSealedBidBatchAuction} from "src/modules/auctions/LSBBA/LSBBA.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

contract CompetitionDeploy is Script {
    AuctionHouse public auctionHouse;
    Catalogue public catalogue;
    LocalSealedBidBatchAuction public lsbba;
    LinearVesting public linearVesting;
    Permit2Clone public permit2Clone;

    function deploy() public {
        vm.startBroadcast();

        // Only needed on Blast testnet, since there isn't a Permit2 deployed
        permit2Clone = new Permit2Clone();
        console2.log("Permit2Clone deployed at: ", address(permit2Clone));

        auctionHouse = new AuctionHouse(msg.sender, address(permit2Clone));
        console2.log("AuctionHouse deployed at: ", address(auctionHouse));

        catalogue = new Catalogue(address(auctionHouse));
        console2.log("Catalogue deployed at: ", address(catalogue));

        lsbba = new LocalSealedBidBatchAuction(address(auctionHouse));
        console2.log("LocalSealedBidBatchAuction deployed at: ", address(lsbba));

        auctionHouse.installModule(lsbba);
        console2.log("LocalSealedBidBatchAuction installed at AuctionHouse");

        linearVesting = new LinearVesting(address(auctionHouse));
        console2.log("LinearVesting deployed at: ", address(linearVesting));

        auctionHouse.installModule(linearVesting);
        console2.log("LinearVesting installed at AuctionHouse");

        vm.stopBroadcast();
    }
}
