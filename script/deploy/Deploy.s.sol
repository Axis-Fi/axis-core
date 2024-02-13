/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// // Scripting libraries
// import {Script, console2} from "forge-std/Script.sol";
// import {stdJson} from "forge-std/StdJson.sol";

// // System contracts
// import {AuctionHouse} from "src/AuctionHouse.sol";

// // Auction modules
// import {LocalSealedBidBatchAuction} from "src/modules/auctions/LSBBA/LSBBA.sol";

// // TODO would it be better to create a system to generate scripts from the sequences instead of having to add them manually to this master script?
// // See the RBS sim bash scripts for how I did this before
// // Is this desirable? Writing scripts in Solidity is supposed to be a good thing
// // The problem is the invocation of the scripts is a pain with the CLI, although this has largely been solved in the batch scripting system by passing in the contract name and function to call
// // However, it's still a bit of a pain to write new scripts each time you need to deploy something new. There is a lot of setup if you need to reference existing contracts

// // Idea
// // CLI system that generates deploy scripts from a sequence file
// // The sequence file would be a JSON file that lists the contracts to be deployed in order, has the paths, args, salts, etc.
// // Two step: generate and run
// // Could generate and review it before running it
// // It also could initialize a local deploy system in an existing forge project
// // This would provide the dependency management that is useful for declarative deployment systems
// // Can probably extend to regular sequential scripts and batch scripts as well

// // TODO can we separate the base of the deploy system from the actual contracts to be deployed

// contract Deploy is Script {
//     using stdJson for string;

//     // Contracts
//     // TODO we would ideally not load every contract in here over time
//     AuctionHouse public auctionHouse;

//     LocalSealedBidBatchAuction public lsbba;

//     // Deploy system storage
//     string public chain;
//     string public env;
//     mapping(string => bytes4) public selectorMap;
//     mapping(string => bytes) public argsMap;
//     mapping(string => bytes32) public saltMap;
//     string[] public deployments;
//     mapping(string => address) public deployedTo;

//     // ========== DEPLOY SYSTEM FUNCTIONS ========== //

//     function _setUp(string calldata chain_, string calldata deployFilePath_) internal {
//         chain = chain_;

//         // Setup contract -> selector mappings
//         // TODO can we automatically infer the selector from the contract name?

//         // Load environment addresses
//         env = vm.readFile("./src/scripts/env.json");

//         // TODO can we automate assignment?

//         // Load deployment data
//         string memory data = vm.readFile(deployFilePath_);

//         // Parse deployment sequence and names
//         bytes memory sequence = abi.decode(data.parseRaw(".sequence"), (bytes));
//         uint256 len = sequence.length;
//         console2.log("Contracts to be deployed:", len);

//         if (len == 0) {
//             return;
//         } else if (len == 1) {
//             // Only one deployment
//             string memory name = abi.decode(data.parseRaw(".sequence..name"), (string));
//             deployments.push(name);
//             console2.log("Deploying", name);
//             // Parse and store args if not kernel
//             // Note: constructor args need to be provided in alphabetical order
//             // due to changes with forge-std or a struct needs to be used
//             if (keccak256(bytes(name)) != keccak256(bytes("AuctionHouse"))) {
//                 argsMap[name] = data.parseRaw(
//                     string.concat(".sequence[?(@.name == '", name, "')].args")
//                 );
//                 saltMap[name] = data.parseBytes32(
//                     string.concat(".sequence[?(@.name == '", name, "')].salt")
//                 );
//             }
//         } else {
//             // More than one deployment
//             string[] memory names = abi.decode(data.parseRaw(".sequence..name"), (string[]));
//             for (uint256 i = 0; i < len; i++) {
//                 string memory name = names[i];
//                 deployments.push(name);
//                 console2.log("Deploying", name);

//                 // Parse and store args if not kernel
//                 // Note: constructor args need to be provided in alphabetical order
//                 // due to changes with forge-std or a struct needs to be used
//                 if (keccak256(bytes(name)) != keccak256(bytes("AuctionHouse"))) {
//                     argsMap[name] = data.parseRaw(
//                         string.concat(".sequence[?(@.name == '", name, "')].args")
//                     );
//                     saltMap[name] = data.parseBytes32(
//                         string.concat(".sequence[?(@.name == '", name, "')].salt")
//                     );
//                 }
//             }
//         }
//     }

//     function envAddress(string memory key_) internal view returns (address) {
//         return env.readAddress(string.concat(".current.", chain, ".", key_));
//     }

//     function deploy(string calldata chain_, string calldata deployFilePath_) external {
//         // Setup
//         _setUp(chain_, deployFilePath_);

//         // Check that deployments is not empty
//         uint256 len = deployments.length;
//         require(len > 0, "No deployments");

//         // If Auction House is to be deployed, then it should be first (not included in contract -> selector mappings so it will error out if not first)
//         bool deployAH = keccak256(bytes(deployments[0])) == keccak256(bytes("AuctionHouse"));
//         if (deployAH) {
//             vm.broadcast();
//             auctionHouse = new AuctionHouse();
//             console2.log("Auction House deployed at:", address(auctionHouse));
//         }

//         // Iterate through deployments
//         for (uint256 i = deployAH ? 1 : 0; i < len; i++) {
//             // Get deploy script selector and deploy args from contract name
//             string memory name = deployments[i];
//             bytes4 selector = selectorMap[name];
//             bytes memory args = argsMap[name];

//             // Call the deploy function for the contract
//             (bool success, bytes memory data) = address(this).call(
//                 abi.encodeWithSelector(selector, args)
//             );
//             require(success, string.concat("Failed to deploy ", deployments[i]));

//             // Store the deployed contract address for logging
//             deployedTo[name] = abi.decode(data, (address));
//         }

//         // Save deployments to file
//         _saveDeployment(chain_);
//     }

//     function _saveDeployment(string memory chain_) internal {
//         // Create file path
//         string memory file = string.concat(
//             "./deployments/",
//             ".",
//             chain_,
//             "-",
//             vm.toString(block.timestamp),
//             ".json"
//         );

//         // Write deployment info to file in JSON format
//         vm.writeLine(file, "{");

//         // Iterate through the contracts that were deployed and write their addresses to the file
//         uint256 len = deployments.length;
//         for (uint256 i; i < len; ++i) {
//             vm.writeLine(
//                 file,
//                 string.concat(
//                     '"',
//                     deployments[i],
//                     '": "',
//                     vm.toString(deployedTo[deployments[i]]),
//                     '",'
//                 )
//             );
//         }
//         vm.writeLine(file, "}");
//     }

// }
