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

- AuctionHouse-derived contracts will be deployed first
- Supported entry keys:
  - `name`: The `name` field corresponds to the function in `Deploy.s.sol` that will be used.
  - `args`: An optional dictionary, in alphabetical order, of arguments that will be provided to the deployment function.
  - `installAtomicAuctionHouse`: An optional boolean that indicates whether the module should be installed in the AtomicAuctionHouse contract.
  - `installBatchAuctionHouse`: An optional boolean that indicates whether the module should be installed in the BatchAuctionHouse contract.

#### Adding A Contract

First, support for the contract needs to be added in the deployment script, `./script/deploy/Deploy.s.sol`.

This involves creating a function in the format of `function deploy<key>(bytes memory args_) public virtual returns (address, string memory)`.

For example, a deployment with `name` set to "AtomicLinearVesting" would require a function to be present in `Deploy.s.sol` with the name `deployAtomicLinearVesting`.

This function should take in the args and salt, in addition to the environment variables, and deploy the contract. It should return the address of the deployed contract, and a string representing the prefix under which the deployed address will be stored. For example, with a returned string of `axis` for a deployment with name `AtomicLinearVesting`, the address would be stored under the `axis.AtomicLinearVesting` key.

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
./script/deploy/deploy.sh --deployFile <file> --broadcast <true | false> --verify <true | false> --save <true | false> --resume <true | false>
```

For example, the following command will deploy using the specified sequence file, broadcast the changes and verify them using Etherscan:

```bash
./script/deploy/deploy.sh --deployFile ./script/deploy/sequences/origin.json --broadcast true --verify true
```

It will also save the deployment addresses to a file and update `env.json`.

To not save the deployment addresses, set the `--save` argument to `false`. For example:

```bash
./script/deploy/deploy.sh --deployFile ./script/deploy/sequences/origin.json --broadcast true --verify true --save false
```

If any problems are faced during deployment (or verification), set the `--resume` argument to `true` in order to resume the previous transaction. For example:

```bash
./script/deploy/deploy.sh --deployFile ./script/deploy/sequences/origin.json --broadcast true --verify true --save true --resume true
```

##### Blast-Specific Version

Deploying on Blast requires an AuctionHouse with additional constructor arguments. For this reason, the `DeployBlast.s.sol` contract script exists, which overrides the deployment behaviour of some contracts. If the chain name contains blast, this deployment script will be used.

Example command:

```bash
CHAIN="blast-sepolia" ./script/deploy/deploy.sh --deployFile ./script/deploy/sequences/origin.json --broadcast true --verify true
```

#### Verification

If the `verify` flag on `deploy.sh` is set, the contract should be verified automatically. If `VERIFIER` is blank or `etherscan`, then `ETHERSCAN_API_KEY` must be set as an environment variable. Additionally, `VERIFIER_URL` can be used to set a custom verifier URL (by default it uses the one configurd in ethers-rs).

If deploying against a Tenderly fork and verifying, [follow the instructions](https://docs.tenderly.co/contract-verification).

## External Dependencies

Note that for each chain Axis is to be deployed on, if the Uniswap V3 DTL callback is to be used, a deployment of G-UNI will be required.

Apart from first-party deployments, the `script/env.json` file contains the addresses of third-party dependencies. These have been sourced from the following locations:

- [Uniswap V2](https://github.com/Uniswap/docs/blob/65d3f21e6cb2879b0672ad791563de0e54fcc089/docs/contracts/v2/reference/smart-contracts/08-deployment-addresses.md)
  - Exceptions
    - Arbitrum Sepolia, Base Sepolia, Blast Sepolia and Mode Sepolia are custom deployments, due to the unavailability of the Uniswap V2 contracts.
- [Uniswap V3](https://github.com/Uniswap/docs/tree/65d3f21e6cb2879b0672ad791563de0e54fcc089/docs/contracts/v3/reference/deployments)
  - Exceptions
    - Arbitrum Sepolia and Blast Sepolia are custom deployments by Axis Finance alongside the G-UNI deployment.
- G-UNI
  - All of the addresses mentioned are custom deployments by Axis Finance. This is because the addresses from the deployments recorded in the [g-uni-v1-core repository](https://github.com/gelatodigital/g-uni-v1-core/tree/bea63422e2155242b051896b635508b7a99d2a1a/deployments) point to proxies, which have since been upgraded to point to Arrakis contracts that have different interfaces.
