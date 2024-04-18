/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";

import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";

contract AuctionHouseSalts is Script, WithEnvironment {
    address internal _envOwner;
    address internal _envPermit2;
    address internal _envProtocol;

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);

        // Cache required variables
        _envOwner = _envAddress("OWNER");
        console2.log("Owner:", _envOwner);
        _envPermit2 = _envAddress("PERMIT2");
        console2.log("Permit2:", _envPermit2);
        _envProtocol = _envAddress("PROTOCOL");
        console2.log("Protocol:", _envProtocol);
    }

    function generate(string calldata chain_) public {
        _setUp(chain_);

        // Calculate salt for the atomic auction house
        bytes memory bytecode = abi.encodePacked(
            type(AtomicAuctionHouse).creationCode, abi.encode(_envOwner, _envProtocol, _envPermit2)
        );
        vm.writeFile("./bytecode/AtomicAuctionHouse.bin", vm.toString(bytecode));

        console2.log("AtomicAuctionHouse bytecode written to ./bytecode/AtomicAuctionHouse.bin");
        console2.log(
            "Run `cast create2 -s <PREFIX> -i $(cat ./bytecode/AtomicAuctionHouse.bin)` to generate the salt"
        );
        console2.log(
            "Then add it to the env.json file under the `current.<CHAIN>.ATOMIC_AUCTION_HOUSE_SALT` key."
        );

        bytecode = abi.encodePacked(
            type(BatchAuctionHouse).creationCode, abi.encode(_envOwner, _envProtocol, _envPermit2)
        );
        vm.writeFile("./bytecode/BatchAuctionHouse.bin", vm.toString(bytecode));

        console2.log("BatchAuctionHouse bytecode written to ./bytecode/BatchAuctionHouse.bin");
        console2.log(
            "Run `cast create2 -s <PREFIX> -i $(cat ./bytecode/BatchAuctionHouse.bin)` to generate the salt"
        );
        console2.log(
            "Then add it to the env.json file under the `current.<CHAIN>.BATCH_AUCTION_HOUSE_SALT` key."
        );
    }
}
