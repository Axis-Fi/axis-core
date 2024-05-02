// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";
import {WithSalts} from "script/salts/WithSalts.s.sol";

// System contracts
import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {AtomicCatalogue} from "src/AtomicCatalogue.sol";
import {BatchCatalogue} from "src/BatchCatalogue.sol";
import {Module} from "src/modules/Modules.sol";

// Auction modules
import {EncryptedMarginalPrice} from "src/modules/auctions/EMP.sol";
import {FixedPriceSale} from "src/modules/auctions/FPS.sol";

// Derivative modules
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

// Callbacks
import {UniswapV2DirectToLiquidity} from "src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";

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

contract Deploy is Script, WithEnvironment, WithSalts {
    using stdJson for string;

    bytes internal constant _ATOMIC_AUCTION_HOUSE_NAME = "AtomicAuctionHouse";
    bytes internal constant _BATCH_AUCTION_HOUSE_NAME = "BatchAuctionHouse";
    bytes internal constant _BLAST_ATOMIC_AUCTION_HOUSE_NAME = "BlastAtomicAuctionHouse";
    bytes internal constant _BLAST_BATCH_AUCTION_HOUSE_NAME = "BlasBatchAuctionHouse";

    // Deploy system storage
    mapping(string => bytes) public argsMap;
    mapping(string => bool) public installAtomicAuctionHouseMap;
    mapping(string => bool) public installBatchAuctionHouseMap;
    string[] public deployments;
    mapping(string => address) public deployedTo;
    uint256[] public auctionHouseIndexes;

    // ========== DEPLOY SYSTEM FUNCTIONS ========== //

    function _setUp(string calldata chain_, string calldata deployFilePath_) internal virtual {
        _loadEnv(chain_);

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

            _configureDeployment(data, name);
        } else {
            // More than one deployment
            string[] memory names = abi.decode(data.parseRaw(".sequence..name"), (string[]));
            for (uint256 i = 0; i < len; i++) {
                string memory name = names[i];
                deployments.push(name);

                _configureDeployment(data, name);
            }
        }
    }

    function deploy(
        string calldata chain_,
        string calldata deployFilePath_,
        bool saveDeployment
    ) external {
        // Setup
        _setUp(chain_, deployFilePath_);

        // Check that deployments is not empty
        uint256 len = deployments.length;
        require(len > 0, "No deployments");

        // Determine the indexes of any AuctionHouse deployments, as those need to be done first
        for (uint256 i; i < len; i++) {
            if (_isAuctionHouse(deployments[i])) {
                auctionHouseIndexes.push(i);
            }
        }

        // Deploy AuctionHouses first
        uint256 ahLen = auctionHouseIndexes.length;
        for (uint256 i; i < ahLen; i++) {
            uint256 index = auctionHouseIndexes[i];
            string memory name = deployments[index];

            if (_isAtomicAuctionHouse(name)) {
                deployedTo[name] = _deployAtomicAuctionHouse();
            } else {
                deployedTo[name] = _deployBatchAuctionHouse();
            }
        }

        // TODO need to get the addresses if just deployed

        // Iterate through deployments
        for (uint256 i; i < len; i++) {
            // Skip if this deployment is an AuctionHouse
            if (_isAuctionHouse(deployments[i])) {
                continue;
            }

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

            // If required, install in the AtomicAuctionHouse
            // For this to work, the deployer address must be the same as the owner of the AuctionHouse (`_envOwner`)
            if (installAtomicAuctionHouseMap[name]) {
                AtomicAuctionHouse atomicAuctionHouse =
                    AtomicAuctionHouse(_envAddressNotZero("axis.AtomicAuctionHouse"));

                console2.log("    Installing in AtomicAuctionHouse");
                vm.broadcast();
                atomicAuctionHouse.installModule(Module(deployedTo[name]));
            }

            // If required, install in the BatchAuctionHouse
            // For this to work, the deployer address must be the same as the owner of the AuctionHouse (`_envOwner`)
            if (installBatchAuctionHouseMap[name]) {
                BatchAuctionHouse batchAuctionHouse =
                    BatchAuctionHouse(_envAddressNotZero("axis.BatchAuctionHouse"));

                console2.log("    Installing in BatchAuctionHouse");
                vm.broadcast();
                batchAuctionHouse.installModule(Module(deployedTo[name]));
            }
        }

        // Save deployments to file
        if (saveDeployment) _saveDeployment(chain_);
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
        for (uint256 i; i < len - 1; ++i) {
            vm.writeLine(
                file,
                string.concat(
                    "\"", deployments[i], "\": \"", vm.toString(deployedTo[deployments[i]]), "\","
                )
            );
        }
        // Write last deployment without a comma
        vm.writeLine(
            file,
            string.concat(
                "\"",
                deployments[len - 1],
                "\": \"",
                vm.toString(deployedTo[deployments[len - 1]]),
                "\""
            )
        );
        vm.writeLine(file, "}");

        // TODO update env.json?
    }

    // ========== AUCTIONHOUSE DEPLOYMENTS ========== //

    function _deployAtomicAuctionHouse() internal virtual returns (address) {
        // No args
        console2.log("");
        console2.log("Deploying AtomicAuctionHouse");

        address owner = _envAddressNotZero("axis.OWNER");
        address permit2 = _envAddressNotZero("axis.PERMIT2");
        address protocol = _envAddressNotZero("axis.PROTOCOL");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "AtomicAuctionHouse",
            type(AtomicAuctionHouse).creationCode,
            abi.encode(owner, protocol, permit2)
        );

        AtomicAuctionHouse atomicAuctionHouse;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            atomicAuctionHouse = new AtomicAuctionHouse(owner, protocol, permit2);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            atomicAuctionHouse = new AtomicAuctionHouse{salt: salt_}(owner, protocol, permit2);
        }
        console2.log("    AtomicAuctionHouse deployed at:", address(atomicAuctionHouse));

        return address(atomicAuctionHouse);
    }

    function _deployBatchAuctionHouse() internal virtual returns (address) {
        // No args
        console2.log("");
        console2.log("Deploying BatchAuctionHouse");

        address owner = _envAddressNotZero("axis.OWNER");
        address permit2 = _envAddressNotZero("axis.PERMIT2");
        address protocol = _envAddressNotZero("axis.PROTOCOL");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BatchAuctionHouse",
            type(BatchAuctionHouse).creationCode,
            abi.encode(owner, protocol, permit2)
        );

        BatchAuctionHouse batchAuctionHouse;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            batchAuctionHouse = new BatchAuctionHouse(owner, protocol, permit2);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            batchAuctionHouse = new BatchAuctionHouse{salt: salt_}(owner, protocol, permit2);
        }
        console2.log("    BatchAuctionHouse deployed at:", address(batchAuctionHouse));

        return address(batchAuctionHouse);
    }

    // ========== CATALOGUE DEPLOYMENTS ========== //

    function deployAtomicCatalogue(bytes memory) public virtual returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying AtomicCatalogue");

        address atomicAuctionHouse = _envAddressNotZero("axis.AtomicAuctionHouse");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "AtomicCatalogue", type(AtomicCatalogue).creationCode, abi.encode(atomicAuctionHouse)
        );

        // Deploy the catalogue
        AtomicCatalogue atomicCatalogue;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            atomicCatalogue = new AtomicCatalogue(atomicAuctionHouse);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            atomicCatalogue = new AtomicCatalogue{salt: salt_}(atomicAuctionHouse);
        }
        console2.log("    AtomicCatalogue deployed at:", address(atomicCatalogue));

        return address(atomicCatalogue);
    }

    function deployBatchCatalogue(bytes memory) public virtual returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying BatchCatalogue");

        address batchAuctionHouse = _envAddressNotZero("axis.BatchAuctionHouse");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "BatchCatalogue", type(BatchCatalogue).creationCode, abi.encode(batchAuctionHouse)
        );

        // Deploy the catalogue
        BatchCatalogue batchCatalogue;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            batchCatalogue = new BatchCatalogue(batchAuctionHouse);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            batchCatalogue = new BatchCatalogue{salt: salt_}(batchAuctionHouse);
        }
        console2.log("    BatchCatalogue deployed at:", address(batchCatalogue));

        return address(batchCatalogue);
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function deployEncryptedMarginalPrice(bytes memory) public virtual returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying EncryptedMarginalPrice");

        address batchAuctionHouse = _envAddressNotZero("axis.BatchAuctionHouse");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "EncryptedMarginalPrice",
            type(EncryptedMarginalPrice).creationCode,
            abi.encode(batchAuctionHouse)
        );

        // Deploy the module
        EncryptedMarginalPrice amEmp;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            amEmp = new EncryptedMarginalPrice(batchAuctionHouse);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            amEmp = new EncryptedMarginalPrice{salt: salt_}(batchAuctionHouse);
        }
        console2.log("    EncryptedMarginalPrice deployed at:", address(amEmp));

        return address(amEmp);
    }

    function deployFixedPriceSale(bytes memory) public virtual returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying FixedPriceSale");

        address atomicAuctionHouse = _envAddressNotZero("axis.AtomicAuctionHouse");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "FixedPriceSale", type(FixedPriceSale).creationCode, abi.encode(atomicAuctionHouse)
        );

        // Deploy the module
        FixedPriceSale amFps;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            amFps = new FixedPriceSale(atomicAuctionHouse);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            amFps = new FixedPriceSale{salt: salt_}(atomicAuctionHouse);
        }
        console2.log("    FixedPriceSale deployed at:", address(amFps));

        return address(amFps);
    }

    function deployAtomicLinearVesting(bytes memory) public virtual returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying LinearVesting (Atomic)");

        address atomicAuctionHouse = _envAddressNotZero("axis.AtomicAuctionHouse");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "LinearVesting", type(LinearVesting).creationCode, abi.encode(atomicAuctionHouse)
        );

        // Deploy the module
        LinearVesting dmAtomicLinearVesting;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            dmAtomicLinearVesting = new LinearVesting(atomicAuctionHouse);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            dmAtomicLinearVesting = new LinearVesting{salt: salt_}(atomicAuctionHouse);
        }
        console2.log("    LinearVesting (Atomic) deployed at:", address(dmAtomicLinearVesting));

        return address(dmAtomicLinearVesting);
    }

    function deployBatchLinearVesting(bytes memory) public virtual returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying LinearVesting (Batch)");

        address batchAuctionHouse = _envAddressNotZero("axis.BatchAuctionHouse");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "LinearVesting", type(LinearVesting).creationCode, abi.encode(batchAuctionHouse)
        );

        // Deploy the module
        LinearVesting dmBatchLinearVesting;
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            dmBatchLinearVesting = new LinearVesting(batchAuctionHouse);
        } else {
            console2.log("    salt:", vm.toString(salt_));

            vm.broadcast();
            dmBatchLinearVesting = new LinearVesting{salt: salt_}(batchAuctionHouse);
        }
        console2.log("    LinearVesting (Batch) deployed at:", address(dmBatchLinearVesting));

        return address(dmBatchLinearVesting);
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function deployAtomicUniswapV2DirectToLiquidity(bytes memory) public returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV2DirectToLiquidity (Atomic)");

        address atomicAuctionHouse = _envAddressNotZero("axis.AtomicAuctionHouse");
        address uniswapV2Factory = _envAddressNotZero("uniswapV2.factory");
        address uniswapV2Router = _envAddressNotZero("uniswapV2.router");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "UniswapV2DirectToLiquidity",
            type(UniswapV2DirectToLiquidity).creationCode,
            abi.encode(atomicAuctionHouse, uniswapV2Factory, uniswapV2Router)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        UniswapV2DirectToLiquidity cbAtomicUniswapV2Dtl = new UniswapV2DirectToLiquidity{
            salt: salt_
        }(atomicAuctionHouse, uniswapV2Factory, uniswapV2Router);
        console2.log(
            "    UniswapV2DirectToLiquidity (Atomic) deployed at:", address(cbAtomicUniswapV2Dtl)
        );

        return address(cbAtomicUniswapV2Dtl);
    }

    function deployBatchUniswapV2DirectToLiquidity(bytes memory) public returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV2DirectToLiquidity (Batch)");

        address batchAuctionHouse = _envAddressNotZero("axis.BatchAuctionHouse");
        address uniswapV2Factory = _envAddressNotZero("uniswapV2.factory");
        address uniswapV2Router = _envAddressNotZero("uniswapV2.router");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "UniswapV2DirectToLiquidity",
            type(UniswapV2DirectToLiquidity).creationCode,
            abi.encode(batchAuctionHouse, uniswapV2Factory, uniswapV2Router)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        UniswapV2DirectToLiquidity cbBatchUniswapV2Dtl = new UniswapV2DirectToLiquidity{salt: salt_}(
            batchAuctionHouse, uniswapV2Factory, uniswapV2Router
        );
        console2.log(
            "    UniswapV2DirectToLiquidity (Batch) deployed at:", address(cbBatchUniswapV2Dtl)
        );

        return address(cbBatchUniswapV2Dtl);
    }

    function deployAtomicUniswapV3DirectToLiquidity(bytes memory) public returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV3DirectToLiquidity (Atomic)");

        address atomicAuctionHouse = _envAddressNotZero("axis.AtomicAuctionHouse");
        address uniswapV3Factory = _envAddressNotZero("uniswapV3.factory");
        address gUniFactory = _envAddressNotZero("gUni.factory");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "UniswapV3DirectToLiquidity",
            type(UniswapV3DirectToLiquidity).creationCode,
            abi.encode(atomicAuctionHouse, uniswapV3Factory, gUniFactory)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        UniswapV3DirectToLiquidity cbAtomicUniswapV3Dtl = new UniswapV3DirectToLiquidity{
            salt: salt_
        }(atomicAuctionHouse, uniswapV3Factory, gUniFactory);
        console2.log(
            "    UniswapV3DirectToLiquidity (Atomic) deployed at:", address(cbAtomicUniswapV3Dtl)
        );

        return address(cbAtomicUniswapV3Dtl);
    }

    function deployBatchUniswapV3DirectToLiquidity(bytes memory) public returns (address) {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV3DirectToLiquidity (Batch)");

        address batchAuctionHouse = _envAddressNotZero("axis.BatchAuctionHouse");
        address uniswapV3Factory = _envAddressNotZero("uniswapV3.factory");
        address gUniFactory = _envAddressNotZero("gUni.factory");

        // Get the salt
        bytes32 salt_ = _getSalt(
            "UniswapV3DirectToLiquidity",
            type(UniswapV3DirectToLiquidity).creationCode,
            abi.encode(batchAuctionHouse, uniswapV3Factory, gUniFactory)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        UniswapV3DirectToLiquidity cbBatchUniswapV3Dtl = new UniswapV3DirectToLiquidity{salt: salt_}(
            batchAuctionHouse, uniswapV3Factory, gUniFactory
        );
        console2.log(
            "    UniswapV3DirectToLiquidity (Batch) deployed at:", address(cbBatchUniswapV3Dtl)
        );

        return address(cbBatchUniswapV3Dtl);
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

    function _isAuctionHouse(string memory deploymentName) internal pure returns (bool) {
        return _isAtomicAuctionHouse(deploymentName) || _isBatchAuctionHouse(deploymentName);
    }

    function _configureDeployment(string memory data_, string memory name_) internal {
        console2.log("    Configuring", name_);

        // Parse and store args
        // Note: constructor args need to be provided in alphabetical order
        // due to changes with forge-std or a struct needs to be used
        argsMap[name_] = _readDataValue(data_, name_, "args");

        // Check if it should be installed in the AtomicAuctionHouse
        if (_readDataBoolean(data_, name_, "installAtomicAuctionHouse")) {
            installAtomicAuctionHouseMap[name_] = true;
        }

        // Check if it should be installed in the BatchAuctionHouse
        if (_readDataBoolean(data_, name_, "installBatchAuctionHouse")) {
            installBatchAuctionHouseMap[name_] = true;
        }
    }

    function _readDataValue(
        string memory data_,
        string memory name_,
        string memory key_
    ) internal pure returns (bytes memory) {
        // This will return "0x" if the key doesn't exist
        return data_.parseRaw(string.concat(".sequence[?(@.name == '", name_, "')].", key_));
    }

    function _readStringValue(
        string memory data_,
        string memory name_,
        string memory key_
    ) internal pure returns (string memory) {
        bytes memory dataValue = _readDataValue(data_, name_, key_);

        // If the key is not set, return an empty string
        if (dataValue.length == 0) {
            return "";
        }

        return abi.decode(dataValue, (string));
    }

    function _readDataBoolean(
        string memory data_,
        string memory name_,
        string memory key_
    ) internal pure returns (bool) {
        bytes memory dataValue = _readDataValue(data_, name_, key_);

        // Comparing `bytes memory` directly doesn't work, so we need to convert to `bytes32`
        return bytes32(dataValue) == bytes32(abi.encodePacked(uint256(1)));
    }
}
