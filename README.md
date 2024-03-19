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
BlastAuctionHouse: [0x000000008D5D105e7e35483B4c03160761A2De5D](https://testnet.blastscan.io/address/0x000000008D5D105e7e35483B4c03160761A2De5D)
Catalogue: [0x742485f9E2de202C5B0a2D540cac6d927FDE230f](https://testnet.blastscan.io/address/0x742485f9E2de202C5B0a2D540cac6d927FDE230f)

**Auction Modules**
BlastEMPAM: [0xe1B83edA3399A2c9B8265215EA21042C9b918dc5](https://testnet.blastscan.io/address/0xe1B83edA3399A2c9B8265215EA21042C9b918dc5)
BlastFPAM: [0x311016478a50d928386d422d44494fb57f9E692b](https://testnet.blastscan.io/address/0x311016478a50d928386d422d44494fb57f9E692b)

**Derivative Modules**
BlastLinearVesting: [0xd13d64dD95F3DB8d1B3E1E65a1ef3F952ee1FC73](https://testnet.blastscan.io/address/0xd13d64dD95F3DB8d1B3E1E65a1ef3F952ee1FC73)

### Arbitrum Sepolia Testnet

**Core Contracts**
AuctionHouse: [0x0000000018430CdB845Ac2fa1CF883a6D94E5ee7](https://sepolia.arbiscan.io/0x0000000018430CdB845Ac2fa1CF883a6D94E5ee7)
Catalogue: [0xA9AEAe1d42bbfa591F4a06945a895d75011bE6e8](https://sepolia.arbiscan.io/0xA9AEAe1d42bbfa591F4a06945a895d75011bE6e8)

**Auction Modules**
EMPAM: [0xe6c04Ce6ca70eeE60bEc40E2e6e62958D91E02CC](https://sepolia.arbiscan.io/0xe6c04Ce6ca70eeE60bEc40E2e6e62958D91E02CC)
FPAM: [0x63Fb97Dd80060cFd70c87Aa54F594F3988B6Fc66](https://sepolia.arbiscan.io/0x63Fb97Dd80060cFd70c87Aa54F594F3988B6Fc66)

**Derivative Modules**
LinearVesting: [0x884E32d3c9D60962EF1A005f3d5365a41CDE38b8](https://sepolia.arbiscan.io/0x884E32d3c9D60962EF1A005f3d5365a41CDE38b8)