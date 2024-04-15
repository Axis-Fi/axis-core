// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

// System contracts
import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {AtomicCatalogue} from "src/AtomicCatalogue.sol";
import {BatchCatalogue} from "src/BatchCatalogue.sol";

// Auction modules
import {EncryptedMarginalPrice} from "src/modules/auctions/EMP.sol";
import {FixedPriceSale} from "src/modules/auctions/FPS.sol";

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

    bytes internal constant _ATOMIC_AUCTION_HOUSE_NAME = "AtomicAuctionHouse";
    bytes internal constant _BATCH_AUCTION_HOUSE_NAME = "BatchAuctionHouse";
    bytes internal constant _BLAST_ATOMIC_AUCTION_HOUSE_NAME = "BlastAtomicAuctionHouse";
    bytes internal constant _BLAST_BATCH_AUCTION_HOUSE_NAME = "BlasBatchAuctionHouse";

    // Environment variables
    address public envOwner;
    address public envPermit2;
    address public envProtocol;

    // Contracts
    // TODO we would ideally not load every contract in here over time
    AtomicAuctionHouse public atomicAuctionHouse;
    BatchAuctionHouse public batchAuctionHouse;
    AtomicCatalogue public atomicCatalogue;
    BatchCatalogue public batchCatalogue;

    EncryptedMarginalPrice public amEmp;
    FixedPriceSale public amFps;
    LinearVesting public dmAtomicLinearVesting;
    LinearVesting public dmBatchLinearVesting;

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
        env = vm.readFile("./script/env.json");

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

        // Check if an AuctionHouse is to be deployed
        bool indexZeroIsAH =
            _isAtomicAuctionHouse(deployments[0]) || _isBatchAuctionHouse(deployments[0]);
        if (indexZeroIsAH) {
            bytes32 salt = saltMap[deployments[0]];

            if (_isAtomicAuctionHouse(deployments[0])) {
                _deployAtomicAuctionHouse(salt);
            } else {
                _deployBatchAuctionHouse(salt);
            }
        }

        // Both AuctionHouses can be deployed in the same script, in which case both the first and second sequence items should be the AuctionHouses
        bool indexOneIsAH = indexZeroIsAH && _isAtomicAuctionHouse(deployments[1])
            || _isBatchAuctionHouse(deployments[1]);
        if (indexOneIsAH) {
            bytes32 salt = saltMap[deployments[1]];

            if (_isAtomicAuctionHouse(deployments[1])) {
                _deployAtomicAuctionHouse(salt);
            } else {
                _deployBatchAuctionHouse(salt);
            }
        }

        uint256 startingIndex = indexOneIsAH ? 2 : indexZeroIsAH ? 1 : 0;

        // Iterate through deployments
        for (uint256 i = startingIndex; i < len; i++) {
            // Get deploy deploy args from contract name
            string memory name = deployments[i];
            // e.g. a deployment named EncryptedMarginalPrice would require the following function: deployEncryptedMarginalPrice(bytes)
            bytes4 selector = bytes4(keccak256(bytes(string.concat("deploy", name, "(bytes)"))));
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
        // Create the deployments folder if it doesn't exist
        if (!vm.isDir("./deployments")) {
            console2.log("Creating deployments directory");

            string[] memory inputs = new string[](2);
            inputs[0] = "mkdir";
            inputs[1] = "deployments";

            vm.ffi(inputs);
        }

        // Create file path
        string memory file =
            string.concat("./deployments/", ".", chain_, "-", vm.toString(block.timestamp), ".json");
        console2.log("Writing deployments to", file);

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

    // ========== AUCTIONHOUSE DEPLOYMENTS ========== //

    function _deployAtomicAuctionHouse(bytes32 salt_) internal {
        console2.log("Deploying AtomicAuctionHouse");

        // No args

        console2.log("    owner:", envOwner);
        console2.log("    permit2:", envPermit2);
        console2.log("    protocol:", envProtocol);

        vm.broadcast();
        atomicAuctionHouse = new AtomicAuctionHouse{salt: salt_}(envOwner, envProtocol, envPermit2);
        console2.log("    AtomicAuctionHouse deployed at:", address(atomicAuctionHouse));
    }

    function _deployBatchAuctionHouse(bytes32 salt_) internal {
        console2.log("Deploying BatchAuctionHouse");

        // No args

        console2.log("    owner:", envOwner);
        console2.log("    permit2:", envPermit2);
        console2.log("    protocol:", envProtocol);

        vm.broadcast();
        batchAuctionHouse = new BatchAuctionHouse{salt: salt_}(envOwner, envProtocol, envPermit2);
        console2.log("    BatchAuctionHouse deployed at:", address(batchAuctionHouse));
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function deployAtomicCatalogue(bytes memory) public returns (address) {
        // No args used

        console2.log("Deploying AtomicCatalogue");
        console2.log("    AtomicAuctionHouse", address(atomicAuctionHouse));

        // Deploy the module
        atomicCatalogue = new AtomicCatalogue(address(atomicAuctionHouse));
        console2.log("    AtomicCatalogue deployed at:", address(atomicCatalogue));

        return address(atomicCatalogue);
    }

    function deployBatchCatalogue(bytes memory) public returns (address) {
        // No args used

        console2.log("Deploying BatchCatalogue");
        console2.log("    BatchAuctionHouse", address(batchAuctionHouse));

        // Deploy the module
        batchCatalogue = new BatchCatalogue(address(batchAuctionHouse));
        console2.log("    BatchCatalogue deployed at:", address(batchCatalogue));

        return address(batchCatalogue);
    }

    function deployEncryptedMarginalPrice(bytes memory) public returns (address) {
        // No args used

        console2.log("Deploying EncryptedMarginalPrice");
        console2.log("    BatchuctionHouse", address(batchAuctionHouse));

        // Deploy the module
        amEmp = new EncryptedMarginalPrice(address(batchAuctionHouse));
        console2.log("    EncryptedMarginalPrice deployed at:", address(amEmp));

        return address(amEmp);
    }

    function deployFixedPriceSale(bytes memory) public returns (address) {
        // No args used

        console2.log("Deploying FixedPriceSale");
        console2.log("    AtomicAuctionHouse", address(atomicAuctionHouse));

        // Deploy the module
        amFps = new FixedPriceSale(address(atomicAuctionHouse));
        console2.log("    FixedPriceSale deployed at:", address(amFps));

        return address(amFps);
    }

    function deployAtomicLinearVesting(bytes memory) public returns (address) {
        // No args used

        console2.log("Deploying LinearVesting (Atomic)");
        console2.log("    AtomicAuctionHouse", address(atomicAuctionHouse));

        // Deploy the module
        dmAtomicLinearVesting = new LinearVesting(address(atomicAuctionHouse));
        console2.log("    LinearVesting (Atomic) deployed at:", address(dmAtomicLinearVesting));

        return address(dmAtomicLinearVesting);
    }

    function deployBatchLinearVesting(bytes memory) public returns (address) {
        // No args used

        console2.log("Deploying LinearVesting (Batch)");
        console2.log("    BatchAuctionHouse", address(batchAuctionHouse));

        // Deploy the module
        dmBatchLinearVesting = new LinearVesting(address(batchAuctionHouse));
        console2.log("    LinearVesting (Batch) deployed at:", address(dmBatchLinearVesting));

        return address(dmBatchLinearVesting);
    }

    // ========== HELPER FUNCTIONS ========== //

    function _isAtomicAuctionHouse(string memory deploymentName) internal pure returns (bool) {
        return keccak256(bytes(deploymentName)) == keccak256(_ATOMIC_AUCTION_HOUSE_NAME)
            || keccak256(bytes(deploymentName)) == keccak256(_BLAST_ATOMIC_AUCTION_HOUSE_NAME);
    }

    function _isBatchAuctionHouse(string memory deploymentName) internal pure returns (bool) {
        return keccak256(bytes(deploymentName)) == keccak256(_BATCH_AUCTION_HOUSE_NAME)
            || keccak256(bytes(deploymentName)) == keccak256(_BLAST_BATCH_AUCTION_HOUSE_NAME);
    }
}
