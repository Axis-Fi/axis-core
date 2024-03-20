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
BlastAuctionHouse: [0x000000009DB7a64d0B3f92E2F0e026a2AF9Cf9b3](https://testnet.blastscan.io/address/0x000000009DB7a64d0B3f92E2F0e026a2AF9Cf9b3)
Catalogue: [0xc94404218178149EBeBfc1F47f0DF14B5FD881C5](https://testnet.blastscan.io/address/0xc94404218178149EBeBfc1F47f0DF14B5FD881C5)

**Auction Modules**
BlastEMPAM: [0xF3e2578C66071a637F06cc02b1c11DeC0784C1A6](https://testnet.blastscan.io/address/0xF3e2578C66071a637F06cc02b1c11DeC0784C1A6)
BlastFPAM: [0x9f3a5566AB27F79c0cF090f70FFc73B7F9962b36](https://testnet.blastscan.io/address/0x9f3a5566AB27F79c0cF090f70FFc73B7F9962b36)

**Derivative Modules**
BlastLinearVesting: [0xDe6D096f14812182F434D164AD6d184cC9A150Fd](https://testnet.blastscan.io/address/0xDe6D096f14812182F434D164AD6d184cC9A150Fd)

### Arbitrum Sepolia Testnet

**Core Contracts**
AuctionHouse: [0x00000000dca78197E4B82b17AFc5C263a097ef3e](https://sepolia.arbiscan.io/address/0x00000000dca78197E4B82b17AFc5C263a097ef3e)
Catalogue: [0x0407910809D251c2E4c217576b63f263e3Fd1B59](https://sepolia.arbiscan.io/address/0x0407910809D251c2E4c217576b63f263e3Fd1B59)

**Auction Modules**
EMPAM: [0x605A7105CA51FD5F107258362f52d8269eeA851A](https://sepolia.arbiscan.io/address/0x605A7105CA51FD5F107258362f52d8269eeA851A)
FPAM: [0x6c80F20C5C0404a3D5349F71F9B25c0654884092](https://sepolia.arbiscan.io/address/0x6c80F20C5C0404a3D5349F71F9B25c0654884092)

**Derivative Modules**
LinearVesting: [0xaC9957282BeA578f371078ddc4cD12A135B105d6](https://sepolia.arbiscan.io/address/0xaC9957282BeA578f371078ddc4cD12A135B105d6)

### Mode Sepolia Testnet

AuctionHouse deployed at:  0x0000000053307d4Ec2141c8b49fff0A04903F11D
Catalogue deployed at:  0x76d2932BE90F1AEd4B7aACeFed9AC8B8b712c8bf
EMPAM deployed at:  0x0407910809D251c2E4c217576b63f263e3Fd1B59
FPAM deployed at:  0x605A7105CA51FD5F107258362f52d8269eeA851A
LinearVesting deployed at:  0x6c80F20C5C0404a3D5349F71F9B25c0654884092

**Core Contracts**
AuctionHouse: [0x0000000053307d4Ec2141c8b49fff0A04903F11D](https://sepolia.explorer.mode.network/address/0x0000000053307d4Ec2141c8b49fff0A04903F11D)
Catalogue: [0x76d2932BE90F1AEd4B7aACeFed9AC8B8b712c8bf](https://sepolia.explorer.mode.network/address/0x76d2932BE90F1AEd4B7aACeFed9AC8B8b712c8bf)

**Auction Modules**
EMPAM: [0x0407910809D251c2E4c217576b63f263e3Fd1B59](https://sepolia.explorer.mode.network/address/0x0407910809D251c2E4c217576b63f263e3Fd1B59)
FPAM: [0x605A7105CA51FD5F107258362f52d8269eeA851A](https://sepolia.explorer.mode.network/address/0x605A7105CA51FD5F107258362f52d8269eeA851A)

**Derivative Modules**
LinearVesting: [0x6c80F20C5C0404a3D5349F71F9B25c0654884092](https://sepolia.explorer.mode.network/address/0x6c80F20C5C0404a3D5349F71F9B25c0654884092)
