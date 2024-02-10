/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";

// Interfaces
import {IPermit2} from "src/lib/permit2/interfaces/IPermit2.sol";

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
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function deploy() public {
        vm.startBroadcast();

        // Assume permit2 is already deployed at canonical address

        auctionHouse = new AuctionHouse(msg.sender, PERMIT2);
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
