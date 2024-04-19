# Deployment

This document provides instructions on how to perform deployments using the available scripts.

## Tasks

### Generating AuctionHouse Salts

For aesthetic reasons, the AuctionHouse contracts may need to be deployed at deterministic addresses.

For the AtomicAuctionHouse and BatchAuctionHouse, a specific script can be used to generate the addresses with a desired prefix.

From the root directory, assuming that the AtomicAuctionHouse address should start with `0xAA` and the BatchAuctionHouse address should start with `0xBB`, the following command would be run:

```bash
./script/deploy/auction_house_salts.sh "AA" "BB"
```

The output would contain the contract-specific salts.

There is also a Blast-specific script at `./script/deploy/auction_house_salts_blast.sh` that can be used.

The salt can then be added into the deployment-specific sequence file under `./script/deploy/sequences/`. For example:

```json
{
    "sequence": [
        {
            "name": "AtomicAuctionHouse",
            "args": {},
            "salt": "0xe7797a9cbbf8b2b2f524066f88eb9567893ccde9d813e7a51d8e5c878bd64776"
        }
    ]
}
```

### Generating Salts for Any Contract

For aesthetic, gas or other reasons, certain contracts will need to be deployed at deterministic addresses.

The following steps need to be followed to generate the salt:

1. Generate the bytecode file and write it to disk. For example:

```solidity
        bytes memory bytecode = abi.encodePacked(
            type(MockCallback).creationCode,
            abi.encode(address(_auctionHouse), Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: true,
                onClaimProceeds: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }), _SELLER)
        );
        vm.writeFile(
            "./bytecode/MockCallback98.bin",
            vm.toString(bytecode)
        );
```

1. Run the salts script with the desired prefix. For example:

```bash
./scripts/deploy/salts.sh ./bytecode/MockCallback98.bin "98"
```

1. The salt can then be added into the deployment-specific sequence file under `./script/deploy/sequences/`. For example:

```json
{
    "sequence": [
        {
            "name": "MockCallback",
            "args": {},
            "salt": "0xe7797a9cbbf8b2b2f524066f88eb9567893ccde9d813e7a51d8e5c878bd64776"
        }
    ]
}
```

### Contract Deployment

There is a deployment script that can be used to deploy any contract for the Axis system.

#### Environment

The `./script/env.json` file contains a per-chain definition of common addresses. These should be populated before deploying to new chains.

#### Sequences

Sequences are JSON files located under the `./script/deploy/sequences/` directory that specify the _sequence_ in which a set of contracts (with their respective arguments and salts) should be deployed.

Notes:

- If an AuctionHouse-derived contract is to be deployed, it must be the first in order.
- If a second AuctionHouse-derived contract is to be deployed, it must be the second in order.
- Supported entry keys:
  - `name`: The `name` field corresponds to the function in `Deploy.s.sol` that will be used.
  - `args`: A dictionary, in alphabetical order, of arguments that will be provided to the deployment function.
  - `salt`: A string that contains the salt in hexadecimal format that will be used to deploy the contract at a deterministic address.
  - `installAtomicAuctionHouse`: An optional boolean that indicates whether the module should be installed in the AtomicAuctionHouse contract.
  - `installBatchAuctionHouse`: An optional boolean that indicates whether the module should be installed in the BatchAuctionHouse contract.

#### Adding A Contract

First, support for the contract needs to be added in the deployment script, `./script/deploy/Deploy.s.sol`.

This involves creating a function in the format of `function deploy<key>(bytes memory args_, bytes32 salt_) public virtual returns (address)`.

For example, a deployment with `name` set to "AtomicLinearVesting" would require a function to be present in `Deploy.s.sol` with the name `deployAtomicLinearVesting`.

This function should take in the args and salt, in addition to the environment variables, and deploy the contract.

#### Running the Deployment

To perform a deployment, run the following script:

```bash
./script/deploy/deploy.sh <sequence file> <broadcast=false> <verify=false>
```

For example, the following command will deploy using the specified sequence file, broadcast the changes and verify them using Etherscan:

```bash
./script/deploy/deploy.sh ./script/deploy/sequences/auctionhouse-mainnet.json true true
```

Following deployment, the addresses should be added into `./script/env.json`.

##### Blast-Specific Version

Deploying on Blast requires an AuctionHouse with additional constructor arguments. For this reason, the `DeployBlast.s.sol` contract script exists, which overrides the deployment behaviour of some contracts.

Example command:

```bash
DEPLOY_SCRIPT="./script/deploy/DeployBlast.s.sol" DEPLOY_CONTRACT="DeployBlast" ./script/deploy/deploy.sh ./script/deploy/sequences/auctionhouse-mainnet.json true true
```
