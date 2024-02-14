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
BlastAuctionHouse: [0x00000000cB3c2A36dEF5Be4d3A674280eFC33498](https://testnet.blastscan.io/address/0x00000000cB3c2A36dEF5Be4d3A674280eFC33498)
Catalogue: [0x0A0BA689D2D72D3f376293c534AF299B3C6Dac85](https://testnet.blastscan.io/address/0x0A0BA689D2D72D3f376293c534AF299B3C6Dac85)

**Auction Modules**
BlastLSBBA: [0xcE56d3E3E145b44597B61E99c64cb82FB209Da04](https://testnet.blastscan.io/address/0xcE56d3E3E145b44597B61E99c64cb82FB209Da04)

**Derivative Modules**
BlastLinearVesting: [0x32A7b69B9F42F0CD6306Bd897ae2664AF0eFBAbd](https://testnet.blastscan.io/address/0x32A7b69B9F42F0CD6306Bd897ae2664AF0eFBAbd)