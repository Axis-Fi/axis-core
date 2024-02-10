## Axis

**Axis is a modular auction protocol.** It supports abstract atomic or batch auction formats, which can be added to the central auction house as modules. Additionally, it allows creating and auctioning derivatives of the base asset in addition to spot tokens. 

The initial version of Axis only supports ERC20 tokens.


## Developer Guide

Axis is built in Solidity using Foundry as the development and test environment. The following commands are available for development:

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

Combines `forge fmt` and `solhint`

```shell
$ pnpm run lint
```
### Scripts

Scripts are written in Solidity using Foundry and are divided into `deploy` and `ops` scripts. Specific scripts are written for individual actions and can be found in the `scripts` directory along with shell scripts to run them.

## Blast Deployment

The initial deployment of Axis will be on the Blast L2 network.

### Blast Sepolia Testnet

**Core Contracts**
BlastAuctionHouse: [0x00000000AD4dd7bC9077e3894225840fE1bfd6eC](https://testnet.blastscan.io/address/0x00000000AD4dd7bC9077e3894225840fE1bfd6eC)
Catalogue: [0x101b502D216d27cb342e9686A2B34A1cD19B2F75](https://testnet.blastscan.io/address/0x101b502D216d27cb342e9686A2B34A1cD19B2F75)

**Auction Modules**
BlastLSBBA: [0xc20918b09dE9708d2A7997dfFc3c5ACB34d4a15b](https://testnet.blastscan.io/address/0xc20918b09dE9708d2A7997dfFc3c5ACB34d4a15b)

**Derivative Modules**
BlastLinearVesting: [0x0e4996960731Fec8E7C9DBbD51383fC71174DD88](https://testnet.blastscan.io/address/0x0e4996960731Fec8E7C9DBbD51383fC71174DD88)