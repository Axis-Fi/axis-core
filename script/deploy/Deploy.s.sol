/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

// System contracts
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Catalogue} from "src/Catalogue.sol";

// Auction modules
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";
import {FixedPriceAuctionModule} from "src/modules/auctions/FPAM.sol";

// Derivative modules
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

// TODO would it be better to create a system to generate scripts from the sequences instead of having to add them manually to this master script?
// See the RBS sim bash scripts for how I did this before
// Is this desirable? Writing scripts in Solidity is supposed to be a good thing
// The problem is the invocation of the scripts is a pain with the CLI, although this has largely been solved in the batch scripting system by passing in the contract name and function to call
// However, it's still a bit of a pain to write new scripts each time you need to deploy something new. There is a lot of setup if you need to reference existing contracts

// Idea
// CLI system that generates deploy scripts from a sequence file
// The sequence file would be a JSON file that lists the contracts to be deployed in order, has the paths, args, salts, etc.
// Two step: generate and run
// Could generate and review it before running it
// It also could initialize a local deploy system in an existing forge project
// This would provide the dependency management that is useful for declarative deployment systems
// Can probably extend to regular sequential scripts and batch scripts as well

// TODO can we separate the base of the deploy system from the actual contracts to be deployed

contract Deploy is Script {
    using stdJson for string;

    bytes internal constant _AUCTION_HOUSE_NAME = "AuctionHouse";
    bytes internal constant _BLAST_AUCTION_HOUSE_NAME = "BlastAuctionHouse";

    // Environment variables
    address public envOwner;
    address public envPermit2;
    address public envProtocol;

    // Contracts
    // TODO we would ideally not load every contract in here over time
    AuctionHouse public auctionHouse;
    Catalogue public catalogue;

    EncryptedMarginalPriceAuctionModule public auctionModuleEmpa;
    FixedPriceAuctionModule public auctionModuleFpa;
    LinearVesting public derivativeModuleLinearVesting;

    // Deploy system storage
    string public chain;
    string public env;
    mapping(string => bytes) public argsMap;
    mapping(string => bytes32) public saltMap;
    string[] public deployments;
    mapping(string => address) public deployedTo;

    // ========== DEPLOY SYSTEM FUNCTIONS ========== //

    function _setUp(string calldata chain_, string calldata deployFilePath_) internal {
        chain = chain_;

        // Load environment addresses
        env = vm.readFile("./src/scripts/env.json");

        envOwner = _envAddress("OWNER");
        envPermit2 = _envAddress("PERMIT2");
        envProtocol = _envAddress("PROTOCOL");

        // TODO can we automate assignment?

        // Load deployment data
        string memory data = vm.readFile(deployFilePath_);

        // Parse deployment sequence and names
        bytes memory sequence = abi.decode(data.parseRaw(".sequence"), (bytes));
        uint256 len = sequence.length;
        console2.log("Contracts to be deployed:", len);

        if (len == 0) {
            return;
        } else if (len == 1) {
            // Only one deployment
            string memory name = abi.decode(data.parseRaw(".sequence..name"), (string));
            deployments.push(name);
            console2.log("Deploying", name);
            // Parse and store args
            // Note: constructor args need to be provided in alphabetical order
            // due to changes with forge-std or a struct needs to be used
            argsMap[name] =
                data.parseRaw(string.concat(".sequence[?(@.name == '", name, "')].args"));
            saltMap[name] =
                bytes32(data.parseRaw(string.concat(".sequence[?(@.name == '", name, "')].salt")));
        } else {
            // More than one deployment
            string[] memory names = abi.decode(data.parseRaw(".sequence..name"), (string[]));
            for (uint256 i = 0; i < len; i++) {
                string memory name = names[i];
                deployments.push(name);
                console2.log("Deploying", name);

                // Parse and store args
                // Note: constructor args need to be provided in alphabetical order
                // due to changes with forge-std or a struct needs to be used
                argsMap[name] =
                    data.parseRaw(string.concat(".sequence[?(@.name == '", name, "')].args"));
                saltMap[name] = bytes32(
                    data.parseRaw(string.concat(".sequence[?(@.name == '", name, "')].salt"))
                );
            }
        }
    }

    function _envAddress(string memory key_) internal view returns (address) {
        return env.readAddress(string.concat(".current.", chain, ".", key_));
    }

    function deploy(string calldata chain_, string calldata deployFilePath_) external {
        // Setup
        _setUp(chain_, deployFilePath_);

        // Check that deployments is not empty
        uint256 len = deployments.length;
        require(len > 0, "No deployments");

        // If Auction House is to be deployed, then it should be first (not included in contract -> selector mappings so it will error out if not first)
        bool deployAH = _isAuctionHouse(deployments[0]);
        if (deployAH) {
            console2.log("Deploying AuctionHouse");

            // No args

            // Fetch salt
            bytes32 salt = saltMap[deployments[0]];

            console2.log("    owner:", envOwner);
            console2.log("    permit2:", envPermit2);
            console2.log("    protocol:", envProtocol);

            vm.broadcast();
            auctionHouse = new AuctionHouse{salt: salt}(envOwner, envProtocol, envPermit2);
            console2.log("    AuctionHouse deployed at:", address(auctionHouse));
        }

        // Iterate through deployments
        for (uint256 i = deployAH ? 1 : 0; i < len; i++) {
            // Get deploy deploy args from contract name
            string memory name = deployments[i];
            // e.g. a deployment named EncryptedMarginalPriceAuctionModule would require the following function: _deployEncryptedMarginalPriceAuctionModule(bytes)
            bytes4 selector = bytes4(bytes(string.concat("_deploy", name, "(bytes)")));
            bytes memory args = argsMap[name];

            // Call the deploy function for the contract
            (bool success, bytes memory data) =
                address(this).call(abi.encodeWithSelector(selector, args));
            require(success, string.concat("Failed to deploy ", deployments[i]));

            // Store the deployed contract address for logging
            deployedTo[name] = abi.decode(data, (address));
        }

        // Save deployments to file
        _saveDeployment(chain_);
    }

    function _saveDeployment(string memory chain_) internal {
        // Create file path
        string memory file =
            string.concat("./deployments/", ".", chain_, "-", vm.toString(block.timestamp), ".json");

        // Write deployment info to file in JSON format
        vm.writeLine(file, "{");

        // Iterate through the contracts that were deployed and write their addresses to the file
        uint256 len = deployments.length;
        for (uint256 i; i < len; ++i) {
            vm.writeLine(
                file,
                string.concat(
                    '"', deployments[i], '": "', vm.toString(deployedTo[deployments[i]]), '",'
                )
            );
        }
        vm.writeLine(file, "}");
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function _deployCatalogue(bytes memory) internal returns (address) {
        // No args used

        console2.log("Deploying Catalogue");
        console2.log("    AuctionHouse", address(auctionHouse));

        // Deploy the module
        catalogue = new Catalogue(address(auctionHouse));
        console2.log("    Catalogue deployed at:", address(catalogue));

        return address(catalogue);
    }

    function _deployEncryptedMarginalPriceAuctionModule(bytes memory) internal returns (address) {
        // No args used

        console2.log("Deploying EncryptedMarginalPriceAuctionModule");
        console2.log("    AuctionHouse", address(auctionHouse));

        // Deploy the module
        auctionModuleEmpa = new EncryptedMarginalPriceAuctionModule(address(auctionHouse));
        console2.log(
            "    EncryptedMarginalPriceAuctionModule deployed at:", address(auctionModuleEmpa)
        );

        return address(auctionModuleEmpa);
    }

    function _deployFixedPriceAuctionModule(bytes memory) internal returns (address) {
        // No args used

        console2.log("Deploying FixedPriceAuctionModule");
        console2.log("    AuctionHouse", address(auctionHouse));

        // Deploy the module
        auctionModuleFpa = new FixedPriceAuctionModule(address(auctionHouse));
        console2.log("    FixedPriceAuctionModule deployed at:", address(auctionModuleFpa));

        return address(auctionModuleFpa);
    }

    function _deployLinearVesting(bytes memory) internal returns (address) {
        // No args used

        console2.log("Deploying LinearVesting");
        console2.log("    AuctionHouse", address(auctionHouse));

        // Deploy the module
        derivativeModuleLinearVesting = new LinearVesting(address(auctionHouse));
        console2.log("    LinearVesting deployed at:", address(derivativeModuleLinearVesting));

        return address(derivativeModuleLinearVesting);
    }

    // ========== HELPER FUNCTIONS ========== //

    function _isAuctionHouse(string memory deploymentName) internal pure returns (bool) {
        return keccak256(bytes(deploymentName)) == keccak256(_AUCTION_HOUSE_NAME)
            || keccak256(bytes(deploymentName)) == keccak256(_BLAST_AUCTION_HOUSE_NAME);
    }
}
