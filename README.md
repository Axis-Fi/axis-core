## Axis

**Axis is a modular auction protocol.** It supports abstract atomic or batch auction formats, which can be added to the central auction house as modules. Additionally, it allows creating and auctioning derivatives of the base asset in addition to spot tokens. 

The initial version of Axis only supports ERC20 tokens.

## Design

Axis implements a modular protocol design, which allows for multiple configurations of derivative and auction markets. Our previous implementation (Bond Protocol) separated custody & tokenization (Teller contracts) and price management (Auctioneer contracts). A central Aggregator contract tracked unique market IDs and provided aggregation view functions as convenience functions for user interfaces. However, the design required redundant Auctioneer contracts to be deployed per Teller, and was challenging to maintain across implementations as improvements were made due to duplicated code.

Axis introduces a simpler architecture design derived from the core purpose of the protocol: to create a generalized system for auctioning derivatives, where “auction” and “derivative” are the key abstractions. 

### Singleton
The core of the protocol is a singleton contract, the **Auction House**, that holds all of the general code required to implement an auction and derivative system, collapsing functionality previously found across several contracts. A key advantage is a reduction in the number of external calls required for common operations, decreasing gas costs. The singleton design is inspired by various efficient DeFi protocols, but most notably OpenSea’s Seaport system. 

### Modules
Auctions and Derivatives are implemented in separate Module contracts which are installed in the AuctionHouse. In this way, logic for individual auctions and derivatives is separate from the core system and must only be implemented once. Additionally, the protocol can be extended after the initial deployment to include new Auction or Derivative types. The module dependency design and management is inspired by the Default Framework (most notably used by OlympusDAO) and ERC-2535 Diamonds.

### Callbacks
Axis implements a callbacks design to allow for flexibility with external integrations during an auction. Inspired heavily by UniswapV4 hooks, callbacks allow for inserting custom logic at various points during an auction including, `onCreate`, `onCancel`, `onCurate`, `onPurchase`, `onBid`, and `onClaimProceeds`. Additionally, the callbacks can optionally be used to receive quote token proceeds from the auction and direct them as desired or source the base tokens that need to be paid out dynamically.

### Auction Types
Axis supports two core auction settlement formats: Atomic Auctions and Batch Auctions. 

Atomicity is a term used to describe a property of most databases (and subsequently blockchains) where a transaction to update the state is applied in its entirety or not at all. Atomic Auctions are then auctions where a bid is submitted, instantly accepted or rejected, and settled within a single transaction. This may be a strange notion to traditional auction theorists. Most auctions do not have this property. The one main exception are Dutch Auctions, in which the price of an item starts at a certain price and decreases over the course of the auction until a buyer bids for the item. When the bid happens, the auction is settled immediately. Thus, the bid is atomic. Atomic auctions have similarities to token exchanges where swaps between assets are executed atomically, and we’ll discuss some implementations which implement features that are common on exchanges.

Batch Auctions refer to the more familiar auction format of collecting bids from participants over a set duration and then settling the auction at the end based on the best received bids. “Batch” refers to the notion that proceeds are received and auction units distributed in a batch, rather than individually.

Two auctions are initially implemented:
- Encrypted Marginal Price Auction (see ./design/EMPA.md for spec), a sealed-bid batch auction
- Fixed Price Auction, simple atomic auction to sell tokens at a fixed price. The CappedMerkleAllowlist callback implementation provides a way to do allowlisted, capped sales at a fixed price for a token. 


## Developer Guide

Axis is built in Solidity using Foundry as the development and test environment. The following commands are available for development:

### Build

```shell
$ forge build
```

### Test

To test the ECIES library, a Rust crate is provided which allows FFI calls to compare the encryption and decryption operations with a reference implementation. This must be built first for those tests to pass. Rust should be installed.
```shell
$ cd crates/ecies && cargo build && cd ../..
```

Then, the test suite can be run with:

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