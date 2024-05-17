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
import {Callbacks} from "src/lib/Callbacks.sol";

// Auction modules
import {EncryptedMarginalPrice} from "src/modules/auctions/batch/EMP.sol";
import {FixedPriceSale} from "src/modules/auctions/atomic/FPS.sol";

// Derivative modules
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

// Callbacks
import {UniswapV2DirectToLiquidity} from "src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";
import {CappedMerkleAllowlist} from "src/callbacks/allowlists/CappedMerkleAllowlist.sol";
import {MerkleAllowlist} from "src/callbacks/allowlists/MerkleAllowlist.sol";
import {TokenAllowlist} from "src/callbacks/allowlists/TokenAllowlist.sol";

/// @notice Declarative deployment script that reads a deployment sequence (with constructor args)
///         and a configured environment file to deploy and install contracts in the Axis protocol.
contract Deploy is Script, WithEnvironment, WithSalts {
    using stdJson for string;

    string internal constant _PREFIX_AXIS = "axis";

    bytes internal constant _ATOMIC_AUCTION_HOUSE_NAME = "AtomicAuctionHouse";
    bytes internal constant _BATCH_AUCTION_HOUSE_NAME = "BatchAuctionHouse";
    bytes internal constant _BLAST_ATOMIC_AUCTION_HOUSE_NAME = "BlastAtomicAuctionHouse";
    bytes internal constant _BLAST_BATCH_AUCTION_HOUSE_NAME = "BlasBatchAuctionHouse";

    // Deploy system storage
    uint256[] public auctionHouseIndexes;
    mapping(string => bytes) public argsMap;
    mapping(string => bool) public installAtomicAuctionHouseMap;
    mapping(string => bool) public installBatchAuctionHouseMap;
    string[] public deployments;

    string[] public deployedToKeys;
    mapping(string => address) public deployedTo;

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
            string memory deploymentKey = string.concat(_PREFIX_AXIS, ".", name);
            deployedToKeys.push(deploymentKey);

            if (_isAtomicAuctionHouse(name)) {
                deployedTo[deploymentKey] = _deployAtomicAuctionHouse();
            } else {
                deployedTo[deploymentKey] = _deployBatchAuctionHouse();
            }
        }

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
            (address deploymentAddress, string memory keyPrefix) =
                abi.decode(data, (address, string));
            string memory deployedToKey = string.concat(keyPrefix, ".", name);

            deployedToKeys.push(deployedToKey);
            deployedTo[deployedToKey] = deploymentAddress;

            // If required, install in the AtomicAuctionHouse
            // For this to work, the deployer address must be the same as the owner of the AuctionHouse (`_envOwner`)
            if (installAtomicAuctionHouseMap[name]) {
                console2.log("");
                AtomicAuctionHouse atomicAuctionHouse =
                    AtomicAuctionHouse(_getAddressNotZero("axis.AtomicAuctionHouse"));

                console2.log("");
                console2.log("    Installing in AtomicAuctionHouse");
                vm.broadcast();
                atomicAuctionHouse.installModule(Module(deploymentAddress));
            }

            // If required, install in the BatchAuctionHouse
            // For this to work, the deployer address must be the same as the owner of the AuctionHouse (`_envOwner`)
            if (installBatchAuctionHouseMap[name]) {
                console2.log("");
                BatchAuctionHouse batchAuctionHouse =
                    BatchAuctionHouse(_getAddressNotZero("axis.BatchAuctionHouse"));

                console2.log("");
                console2.log("    Installing in BatchAuctionHouse");
                vm.broadcast();
                batchAuctionHouse.installModule(Module(deploymentAddress));
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
        uint256 len = deployedToKeys.length;
        for (uint256 i; i < len - 1; ++i) {
            vm.writeLine(
                file,
                string.concat(
                    "\"",
                    deployedToKeys[i],
                    "\": \"",
                    vm.toString(deployedTo[deployedToKeys[i]]),
                    "\","
                )
            );
        }
        // Write last deployment without a comma
        vm.writeLine(
            file,
            string.concat(
                "\"",
                deployedToKeys[len - 1],
                "\": \"",
                vm.toString(deployedTo[deployedToKeys[len - 1]]),
                "\""
            )
        );
        vm.writeLine(file, "}");

        // Update the env.json file
        for (uint256 i; i < len; ++i) {
            string memory key = deployedToKeys[i];
            address value = deployedTo[key];

            string[] memory inputs = new string[](3);
            inputs[0] = "./script/deploy/write_deployment.sh";
            inputs[1] = string.concat("current", ".", chain_, ".", key);
            inputs[2] = vm.toString(value);

            vm.ffi(inputs);
        }
    }

    // ========== AUCTIONHOUSE DEPLOYMENTS ========== //

    function _deployAtomicAuctionHouse() internal virtual returns (address) {
        // No args
        console2.log("");
        console2.log("Deploying AtomicAuctionHouse");

        address owner = _getAddressNotZero("axis.OWNER");
        address protocol = _getAddressNotZero("axis.PROTOCOL");
        address permit2 = _getAddressNotZero("axis.PERMIT2");

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
        console2.log("");
        console2.log("    AtomicAuctionHouse deployed at:", address(atomicAuctionHouse));

        return address(atomicAuctionHouse);
    }

    function _deployBatchAuctionHouse() internal virtual returns (address) {
        // No args
        console2.log("");
        console2.log("Deploying BatchAuctionHouse");

        address owner = _getAddressNotZero("axis.OWNER");
        address protocol = _getAddressNotZero("axis.PROTOCOL");
        address permit2 = _getAddressNotZero("axis.PERMIT2");

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
        console2.log("");
        console2.log("    BatchAuctionHouse deployed at:", address(batchAuctionHouse));

        return address(batchAuctionHouse);
    }

    // ========== CATALOGUE DEPLOYMENTS ========== //

    function deployAtomicCatalogue(bytes memory) public virtual returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying AtomicCatalogue");

        address atomicAuctionHouse = _getAddressNotZero("axis.AtomicAuctionHouse");

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
        console2.log("");
        console2.log("    AtomicCatalogue deployed at:", address(atomicCatalogue));

        return (address(atomicCatalogue), _PREFIX_AXIS);
    }

    function deployBatchCatalogue(bytes memory) public virtual returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying BatchCatalogue");

        address batchAuctionHouse = _getAddressNotZero("axis.BatchAuctionHouse");

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
        console2.log("");
        console2.log("    BatchCatalogue deployed at:", address(batchCatalogue));

        return (address(batchCatalogue), _PREFIX_AXIS);
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function deployEncryptedMarginalPrice(bytes memory)
        public
        virtual
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying EncryptedMarginalPrice");

        address batchAuctionHouse = _getAddressNotZero("axis.BatchAuctionHouse");

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
        console2.log("");
        console2.log("    EncryptedMarginalPrice deployed at:", address(amEmp));

        return (address(amEmp), _PREFIX_AXIS);
    }

    function deployFixedPriceSale(bytes memory) public virtual returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying FixedPriceSale");

        address atomicAuctionHouse = _getAddressNotZero("axis.AtomicAuctionHouse");

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
        console2.log("");
        console2.log("    FixedPriceSale deployed at:", address(amFps));

        return (address(amFps), _PREFIX_AXIS);
    }

    function deployAtomicLinearVesting(bytes memory)
        public
        virtual
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying LinearVesting (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("axis.AtomicAuctionHouse");

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
        console2.log("");
        console2.log("    LinearVesting (Atomic) deployed at:", address(dmAtomicLinearVesting));

        return (address(dmAtomicLinearVesting), _PREFIX_AXIS);
    }

    function deployBatchLinearVesting(bytes memory)
        public
        virtual
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying LinearVesting (Batch)");

        address batchAuctionHouse = _getAddressNotZero("axis.BatchAuctionHouse");

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
        console2.log("");
        console2.log("    LinearVesting (Batch) deployed at:", address(dmBatchLinearVesting));

        return (address(dmBatchLinearVesting), _PREFIX_AXIS);
    }

    // ========== MODULE DEPLOYMENTS ========== //

    function deployAtomicUniswapV2DirectToLiquidity(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV2DirectToLiquidity (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("axis.AtomicAuctionHouse");
        address uniswapV2Factory = _getAddressNotZero("uniswapV2.factory");
        address uniswapV2Router = _getAddressNotZero("uniswapV2.router");

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
        console2.log("");
        console2.log(
            "    UniswapV2DirectToLiquidity (Atomic) deployed at:", address(cbAtomicUniswapV2Dtl)
        );

        return (address(cbAtomicUniswapV2Dtl), _PREFIX_AXIS);
    }

    function deployBatchUniswapV2DirectToLiquidity(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV2DirectToLiquidity (Batch)");

        address batchAuctionHouse = _getAddressNotZero("axis.BatchAuctionHouse");
        address uniswapV2Factory = _getAddressNotZero("uniswapV2.factory");
        address uniswapV2Router = _getAddressNotZero("uniswapV2.router");

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
        console2.log("");
        console2.log(
            "    UniswapV2DirectToLiquidity (Batch) deployed at:", address(cbBatchUniswapV2Dtl)
        );

        return (address(cbBatchUniswapV2Dtl), _PREFIX_AXIS);
    }

    function deployAtomicUniswapV3DirectToLiquidity(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV3DirectToLiquidity (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("axis.AtomicAuctionHouse");
        address uniswapV3Factory = _getAddressNotZero("uniswapV3.factory");
        address gUniFactory = _getAddressNotZero("gUni.factory");

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
        console2.log("");
        console2.log(
            "    UniswapV3DirectToLiquidity (Atomic) deployed at:", address(cbAtomicUniswapV3Dtl)
        );

        return (address(cbAtomicUniswapV3Dtl), _PREFIX_AXIS);
    }

    function deployBatchUniswapV3DirectToLiquidity(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV3DirectToLiquidity (Batch)");

        address batchAuctionHouse = _getAddressNotZero("axis.BatchAuctionHouse");
        address uniswapV3Factory = _getAddressNotZero("uniswapV3.factory");
        address gUniFactory = _getAddressNotZero("gUni.factory");

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
        console2.log("");
        console2.log(
            "    UniswapV3DirectToLiquidity (Batch) deployed at:", address(cbBatchUniswapV3Dtl)
        );

        return (address(cbBatchUniswapV3Dtl), _PREFIX_AXIS);
    }

    function deployAtomicCappedMerkleAllowlist(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying CappedMerkleAllowlist (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("axis.AtomicAuctionHouse");
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            "CappedMerkleAllowlist",
            type(CappedMerkleAllowlist).creationCode,
            abi.encode(atomicAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        CappedMerkleAllowlist cbAtomicCappedMerkleAllowlist =
            new CappedMerkleAllowlist{salt: salt_}(atomicAuctionHouse, permissions);
        console2.log("");
        console2.log(
            "    CappedMerkleAllowlist (Atomic) deployed at:",
            address(cbAtomicCappedMerkleAllowlist)
        );

        return (address(cbAtomicCappedMerkleAllowlist), _PREFIX_AXIS);
    }

    function deployBatchCappedMerkleAllowlist(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying CappedMerkleAllowlist (Batch)");

        address batchAuctionHouse = _getAddressNotZero("axis.BatchAuctionHouse");
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            "CappedMerkleAllowlist",
            type(CappedMerkleAllowlist).creationCode,
            abi.encode(batchAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        CappedMerkleAllowlist cbBatchCappedMerkleAllowlist =
            new CappedMerkleAllowlist{salt: salt_}(batchAuctionHouse, permissions);
        console2.log("");
        console2.log(
            "    CappedMerkleAllowlist (Batch) deployed at:", address(cbBatchCappedMerkleAllowlist)
        );

        return (address(cbBatchCappedMerkleAllowlist), _PREFIX_AXIS);
    }

    function deployAtomicMerkleAllowlist(bytes memory) public returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying MerkleAllowlist (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("axis.AtomicAuctionHouse");
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            "MerkleAllowlist",
            type(MerkleAllowlist).creationCode,
            abi.encode(atomicAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        MerkleAllowlist cbAtomicMerkleAllowlist =
            new MerkleAllowlist{salt: salt_}(atomicAuctionHouse, permissions);
        console2.log("");
        console2.log("    MerkleAllowlist (Atomic) deployed at:", address(cbAtomicMerkleAllowlist));

        return (address(cbAtomicMerkleAllowlist), _PREFIX_AXIS);
    }

    function deployBatchMerkleAllowlist(bytes memory) public returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying MerkleAllowlist (Batch)");

        address batchAuctionHouse = _getAddressNotZero("axis.BatchAuctionHouse");
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            "MerkleAllowlist",
            type(MerkleAllowlist).creationCode,
            abi.encode(batchAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        MerkleAllowlist cbBatchMerkleAllowlist =
            new MerkleAllowlist{salt: salt_}(batchAuctionHouse, permissions);
        console2.log("");
        console2.log("    MerkleAllowlist (Batch) deployed at:", address(cbBatchMerkleAllowlist));

        return (address(cbBatchMerkleAllowlist), _PREFIX_AXIS);
    }

    function deployAtomicTokenAllowlist(bytes memory) public returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying TokenAllowlist (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("axis.AtomicAuctionHouse");
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            "TokenAllowlist",
            type(TokenAllowlist).creationCode,
            abi.encode(atomicAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        TokenAllowlist cbAtomicTokenAllowlist =
            new TokenAllowlist{salt: salt_}(atomicAuctionHouse, permissions);
        console2.log("");
        console2.log("    TokenAllowlist (Atomic) deployed at:", address(cbAtomicTokenAllowlist));

        return (address(cbAtomicTokenAllowlist), _PREFIX_AXIS);
    }

    function deployBatchTokenAllowlist(bytes memory) public returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying TokenAllowlist (Batch)");

        address batchAuctionHouse = _getAddressNotZero("axis.BatchAuctionHouse");
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            "TokenAllowlist",
            type(TokenAllowlist).creationCode,
            abi.encode(batchAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        TokenAllowlist cbBatchTokenAllowlist =
            new TokenAllowlist{salt: salt_}(batchAuctionHouse, permissions);
        console2.log("");
        console2.log("    TokenAllowlist (Batch) deployed at:", address(cbBatchTokenAllowlist));

        return (address(cbBatchTokenAllowlist), _PREFIX_AXIS);
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

    /// @notice Get an address for a given key
    /// @dev    This variant will first check for the key in the
    ///         addresses from the current deployment sequence (stored in `deployedTo`),
    ///         followed by the contents of `env.json`.
    ///
    ///         If no value is found for the key, or it is the zero address, the function will revert.
    ///
    /// @param  key_    Key to look for
    /// @return address Returns the address
    function _getAddressNotZero(string memory key_) internal view returns (address) {
        // Get from the deployed addresses first
        address deployedAddress = deployedTo[key_];

        if (deployedAddress != address(0)) {
            console2.log("    %s: %s (from deployment addresses)", key_, deployedAddress);
            return deployedAddress;
        }

        return _envAddressNotZero(key_);
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
