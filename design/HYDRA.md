# HYDRA: Hybrid Decentralized Auctions

HYDRA (name TBD) is a hybrid on-chain/off-chain, sealed bid batch auction system built on the Axis Protocol that uses a variety of "web3" technology to achieve a strong balance between user experience, security, efficiency, and decentralization. The purpose of the system is to allow any seller to create sealed bid batch auctions for any ERC20 token pair. Buyers place bids off-chain on a decentralized UI where they are encrypted using a decentralized key management protocol and stored in a decentralized database. When the auction ends, a web3 function is executed to settle the auction. The settlement is verified with a validity proof on the auction contract, and the provenance of the bid data is ensured by protocol ownership of the execution function. The experience is gasless for buyers. Sellers post a transaction to the network when creating an auction, but do not have to execute additional transactions to settle the auction. A fee is taken from the auction proceeds and used is to compensate the settlement executor.

## User Features

### Sellers
- Permissionlessly create sealed bid batch auctions, which improve execution over open bid auctions
- Auctions can be created for any ERC20 token pair
- Two transactions to create auction: 1. approve base token (if not already), 2. create auction
- Settlement handled by protocol in a transparent and verifiable way
- Settlement fees are minimal due to complex logic being executed off-chain
- Can limit auction participants using an allowlist
- Can use hooks to customize transfer logic for auction proceeds
- Can create and auction a derivative of the base token if desired
- Can enforce a minimum price and minimum capacity filled in order for auction to settle

### Buyers
- Gasless experience: pay nothing if your bid is not executed
- Permissionlessly place bids on any auction
- Bids are encrypted using a decentralized key management protocol so that no one can peek at your bids
- Settlement handled by protocol in a transparent and verifiable way


## Components and Design Decisions
TODO

### Decentralization throughout the stack
TODO: most dapps are centralized in some way, but we can do better

### Smart Contracts

#### Axis Protocol
  - Auction House
  - EMPBA (includes ZK verifier for settlement proofs)

#### Permit2 Approvals
TODO: Gasless for buyers after initial approval
[Permit2](https://github.com/Uniswap/permit2): Signature-based approvals for any ERC20 token
  - [Integration Guide](https://blog.uniswap.org/permit2-integration-guide)

#### ZK Validity Proof of Settlement Logic
TODO: need to determine if we're actually going to do this. if the settlement address is compromised, a valid proof can be generated against the wrong data set
[Circom2 ZK Circuit Compiler](https://docs.circom.io/getting-started)

### Web3 Functions
Challenges: Bid Provenance problem, on-chain funding problem, gasless for sellers
Need: Trusted but Decentralized Execution of Settlement Logic
Solution:
[Gelato Web3 Functions](https://www.gelato.network/web3-functions): Automate smart contracts with off-chain logic and execution
  - [Typescript Functions](https://docs.gelato.network/developer-services/web3-functions/understanding-web3-functions/typescript-function)
  - [Create Task from Smart Contract](https://docs.gelato.network/developer-services/web3-functions/understanding-web3-functions/create-a-web3-function-task/using-a-smart-contract)

### Encryption Key Management
What: Need to be able to encrypt bids and other data with a key that no interested party controls until the auction ends. This is to prevent insider dealing or other bad behavior.

Solution:
[Lit Protocol](https://litprotocol.com): Decentralized key management protocol that can be used to generate a key pair, encrypt data, and decrypt the data based on certain conditions (e.g. a timelock).
- [Timelock Example](https://developer.litprotocol.com/v3/sdk/access-control/evm/timelock)
- [Encryption](https://developer.litprotocol.com/v3/sdk/access-control/encryption)

### UI
SPA hosted on [IPFS](https://docs.ipfs.tech/how-to/websites-on-ipfs/single-page-website/) with [Eth.limo](https://eth.limo/) domain resolution to ENS owned by the protocol

### Database
[OrbitDB](https://orbitdb.org/): decentralized database on IPFS, append-only

## Actions

### Seller Creates Auction
```mermaid
sequenceDiagram
  autoNumber
  participant Seller
  participant UI
  participant Database
  participant Lit Protocol
  participant Gelato
  participant AuctionHouse
  participant EMPBA

  Seller->>UI: Navigate to Create Auction page
  activate UI
    Seller->>UI: Input auction data (baseToken, quoteToken, start, duration, minPrice, capacity, optionally hooks, allowlist, and derivative data)
    Seller->>UI: Click "Create Auction"
    UI->>Lit Protocol: Create new BLS keypair for encryption that is revealed via Timelock at start + duration
    Lit Protocol-->UI: Generated Public Key
    UI->>Database: Store reference to Lit Protocol key info (which won't be decrypted until auction ends)
    UI->>UI: Encrypt minPrice with public key
    UI->>UI: Create transaction to create auction with input data + encrypted minPrice + public key + auctionType
    UI-->Seller: Present transaction to Seller to sign
    Seller->>UI: Sign transaction to create auction
    UI->>AuctionHouse: Send transaction to blockchain 
    activate AuctionHouse
        AuctionHouse->>AuctionHouse: Validate and store routing & derivative parameters
        AuctionHouse->>EMPBA: Call auction module with auction params and lot ID
        activate EMPBA
            EMPBA->>EMPBA: Validate and store auction parameters
            EMPBA->>Gelato: Create task to settle the auction after it concludes
            EMPBA-->AuctionHouse: Hand execution back to AuctionHouse
        deactivate EMPBA
        AuctionHouse-->UI: Finish execution and return result
    deactivate AuctionHouse
    UI-->Seller: Show transaction status
  deactivate UI
```

### Buyer Places Bid
```mermaid
sequenceDiagram
  autoNumber
  participant Buyer
  participant UI
  participant Database
  participant Permit2
  participant AuctionHouse
  participant EMPBA

  Buyer->>UI: Navigate to Auction page
  UI->>AuctionHouse: Fetch data for auction ID (base token, quote token, public key, start, conclusion, auction type, derivative type + info, capacity, min bid size)
  AuctionHouse->>EMPBA: Get data stored on module to return
  AuctionHouse-->UI: Return results
  UI-->Buyer: Display data for user
  Buyer->>UI: Input bid data (amount, minAmountOut)
  UI->>Permit2: Check user's approval for quote token
  alt user hasn't approved Permit2
    UI-->Buyer: Display "Approve Permit2" button
    Buyer->>UI: Click "Approve Permit2" button
    UI-->Buyer: Display transaction for signing
    Buyer->>UI: Sign approval transaction
    UI->>Permit2: Send approval transaction
    Permit2-->UI: Return execution result
  end
  UI-->Buyer: Display "Place bid" button
  Buyer->>UI: Click "Place bid" button
  UI->>UI: Construct permit2 approval for AuctionHouse
  UI-->Buyer: Display permit2 signature request
  Buyer->>UI: Sign permit2 signature request
  UI->>UI: Construct bid typed data object for signing
  UI-->Buyer: Display bid typed data signature request (this is in plaintext for user to verify)
  UI->>UI: Encrypt bidder, recipient, amount & minAmountOut with public key from auction
  UI->>UI: Construct database entry with encrypted data, permit2 approval signature, and typed data signature
  UI->>Database: Write database entry to decentralized database (append-only)
  UI-->Buyer: Display submission result to user
```


### Auction Settled via Web3 Function
```mermaid
sequenceDiagram
  autoNumber
  participant Gelato Keeper
  participant Settlement Function
  participant IPFS
  participant Database
  participant Lit Protocol
  participant AuctionHouse
  participant EMPBA

  Note over Gelato Keeper: Configured to execute by the EMPBA after auction concludes when created
  Gelato Keeper->>IPFS: Fetch settlement code from provided IPFS hash
  activate Gelato Keeper
    Gelato Keeper->>Settlement Function: Execute settlement function
    activate Settlement Function
        Settlement Function->>Database: Get Lit protocol reference for provided auction ID
        Settlement Function->>Lit Protocol: Request private key for reference key pair (should be available now that timelock is up)
        Settlement Function->>EMPBA: Get min price for auction and decrypt it with key
        Settlement Function->>Database: Get all bids for auction ID
        Settlement Function->>Settlement Function: Iterate through all bids, decrypting and sorting them. Apply filtering logic (no approval, too small, price too low)
        Settlement Function->>Settlement Function: Determine if auction can be settled. If so, determine marginal price.
        Settlement Function->>Settlement Function: Calculate amounts out for winners
        Settlement Function->>Settlement Function: Create ZK validity proof of results (hand-wavy atm)
        Settlement Function->>Settlement Function: Construct settlement transaction (id, winning bids (original signed ones), amountsOut, permit2 signatures, bid signatures, zk proof of settlement)
        Settlement Function->>AuctionHouse: Send settlement transaction to blockchain
        activate AuctionHouse
            AuctionHouse->>EMPBA: Validate bid signatures, ZK proof, minimum price, and minimum bid sizes
            EMPBA-->AuctionHouse: Hand execution back to AuctionHouse
            AuctionHouse->>AuctionHouse: Validate and execute permit2 approvals
            AuctionHouse->>AuctionHouse: Transfer payments and payouts
            AuctionHouse-->Settlement Function: Return transaction result
        deactivate AuctionHouse
        Settlement Function->>Settlement Function: Handle result cases via Callback functions
        Settlement Function-->Gelato Keeper: Complete execution
    deactivate Settlement Function
deactivate Gelato Keeper
Note over Gelato Keeper: Execution is paid for by the protocol in a separate transaction to Gelato
```






