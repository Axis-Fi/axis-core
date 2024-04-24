# Deployment

This document provides instructions on how to perform deployments using the available scripts.

## Requirements

- `forge`
  - Ensure that the version is at least on or after `nightly-008922d5165c764859bc540d7298045eebf5bc60` (due to [foundry#7713](https://github.com/foundry-rs/foundry/pull/7713))

## Tasks

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
  - `installAtomicAuctionHouse`: An optional boolean that indicates whether the module should be installed in the AtomicAuctionHouse contract.
  - `installBatchAuctionHouse`: An optional boolean that indicates whether the module should be installed in the BatchAuctionHouse contract.

#### Adding A Contract

First, support for the contract needs to be added in the deployment script, `./script/deploy/Deploy.s.sol`.

This involves creating a function in the format of `function deploy<key>(bytes memory args_) public virtual returns (address)`.

For example, a deployment with `name` set to "AtomicLinearVesting" would require a function to be present in `Deploy.s.sol` with the name `deployAtomicLinearVesting`.

This function should take in the args and salt, in addition to the environment variables, and deploy the contract.

Notes:

- All contract deployments/actions must be pre-pended by a `vm.broadcast()` or `vm.startBroadcast()` call. A failure to do so will result in the action not being published to the chain.
- If the salt is specified during contract deployment and the deployment is attempted again, there will be a collision error. This applies event if the salt is not defined (`bytes32(0)`). For this reason, the contract deployment code should check for a zero value. For example:

```solidity
        if (salt_ == bytes32(0)) {
            vm.broadcast();
            amEmp = new EncryptedMarginalPrice(address(batchAuctionHouse));
        } else {
            vm.broadcast();
            amEmp = new EncryptedMarginalPrice{salt: salt_}(address(batchAuctionHouse));
        }
```

#### Running the Deployment

To perform a deployment, run the following script:

```bash
./script/deploy/deploy.sh < sequence_file > [broadcast=false] [verify=false] [resume=false]
```

For example, the following command will deploy using the specified sequence file, broadcast the changes and verify them using Etherscan:

```bash
./script/deploy/deploy.sh ./script/deploy/sequences/auctionhouse-mainnet.json true true
```

Following deployment, the addresses need to be manually added into `./script/env.json`.

If any problems are faced during deployment (or verification), set the third boolean argument to `true` in order to resume the previous transaction. For example:

```bash
./script/deploy/deploy.sh ./script/deploy/sequences/auctionhouse-mainnet.json true true true
```

##### Blast-Specific Version

Deploying on Blast requires an AuctionHouse with additional constructor arguments. For this reason, the `DeployBlast.s.sol` contract script exists, which overrides the deployment behaviour of some contracts. If the chain name contains blast, this deployment script will be used.

Example command:

```bash
CHAIN="blast-testnet" ./script/deploy/deploy.sh ./script/deploy/sequences/auctionhouse-mainnet.json true true
```

#### Verification

If the `verify` flag on `deploy.sh` is set, the contract should be verified automatically. This requires the following environment variables to be set on the command-line or in `.env`:

- `ETHERSCAN_API_KEY`

If deploying against a Tenderly fork and verifying, [follow the instructions](https://docs.tenderly.co/contract-verification).
