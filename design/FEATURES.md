# Axis Features

## Terminology

Lot

-   _What_ is being sold
-   A token or group of tokens that are available for bidding through an auction
-   The current design supports a single lot per auction

Auction

-   The auction (specifically the type) specifies _how_ the lot is being sold

Quote Token

-   The token that is offered by the bidder and received by the seller in return for the base token

Base Token

-   The token that is provided to the bidder in exchange for the quote token
-   If the auction is for a derivative of the base token, then the bidder receives the derivative on purchase or settlement instead of the base token.

Derivative Token

-   A derivative of a base token that a bidder may receive instead of the base token for an auction

## Actions

Auction

-   Create an auction for a lot starting immediately or at some point in the future.

Cancel Auction

-   Ends the auction immediately/prematurely
-   Further capacity cannot be sold nor bids/purchases accepted
-   Valid for all auction types
-   In the case of a batch auction, the auction can only be cancelled before it starts.

Curate

-   Accept proposed curation of an auction. Curation is where a third-party vouches for an auction issuer. They may receive a fee.

Purchase

-   _Immediately_ buy tokens from an auction
-   Provided the auction is open and the purchase amount is within capacity, the purchase will succeed
-   Valid only for atomic auctions (since batch auctions are settled later)

Bid

-   An offer to buy tokens from an auction
-   The success of the bid is not known until the auction is settled
-   Valid only for batch auctions (since atomic auctions are settled at the same time)

Settle

-   Finalises the bids for an auction
-   Valid only for batch auctions (since atomic auctions are settled at the same time)

Claim Bid

-   Bidder claims payout or refund for a bid submitted on a batch auction.

Claim Proceeds

-   Seller claims proceeds received from a batch auction. An optional callback can be implemented to direct the proceeds of the auction.

## Features



### Flexibility in Storage and Computation

Bond Protocol V1 required bids to be stored on-chain and auctions to be settled on-chain. Not all auction types are suited to this.

core system only supports atomic auctions. Batch auctions not supported. Except through Gnosis Auctions, which is entirely on-chain.

For this reason, V2 supports off-chain bids and settlement computation. This enables auctions that were not possible earlier:

-   sealed bid auctions
    -   list of winning bidders provided to the contract for settlement
-   providing Bond Protocol auctions as a liquidity source for CoW Protocol
-   off-chain computation of auction settlement by solvers

solver is trying to put together a set of contract interactions that gives an ideal outcome for users

limit order system is a version of intents. Custom settlement contract.

sweet spot for GDA to do a TWAP swap. Solvers can plug into it. Better than FraxSwap TWAP (req ext liquidity) or CoW Swap TWAP (paying gas every time)
OTC swap is an exchange between parties without 3PL

sealed batch auctions could be done on-chain, but are difficult

### Auction Types

Atomic

-   Definition
    -   From the whitepaper:
        > Atomic Auctions are then auctions where a bid is submitted, instantly accepted or rejected, and settled within a single transaction
    -   Atomic auctions are settled at the time of purchase
    -   Settled immediately: offered tokens are transferred at time of purchase
-   Examples include:
    -   Sequential Dutch
        > The main feature of an SDA includes splitting a large number of tokens into multiple discrete Dutch Auctions that are performed over time. This sequence of auctions uses a dynamic exchange rate for two arbitrary ERC20 tokens without the use of oracles.
    -   Gradual Dutch / Australian Auctions
        > while SDAs split capacity into multiple discrete auctions, GDAs split capacity into infinitely many auctions
        -   The cumulative purchase price is increasing exponentially

Batch

-   Definition
    -   From the whitepaper:
        > Batch Auctions refer to the more familiar auction format of collecting bids from participants over a set duration and then settling the auction at the end based on the best received bids. “Batch” refers to the notion that proceeds are received and auction units distributed in a batch, rather than individually.
    -   Two major types:
        -   Open
            -   Bids are recorded on-chain
        -   Sealed
            -   Bids are recorded off-chain and submitted on-chain at the time of settlement
            -   The submission function will be permissioned in order to restrict who can submit the set of sealed bids
            -   This auction type prevents other bidders from seeing active bids
    -   Quote tokens are only transferred at the time of settlement
        -   This avoids having to provide functionality for bidders to claim a refund of their quote tokens
    -   Payout tokens are transferred at the time of settlement
-   Examples include:
    -   Marginal Price Auction
        > A marginal price auction, also called a uniform price auction, is a multiunit auction format where bidders place bids that include two variables: price and quantity of items to purchase. The auction is settled by awarding the items to the highest bids until capacity is expended. All winners pay the lowest accepted bid price. The price of this lowest accepted bid is also called the clearing price of the auction.
    -   Vickrey-Clarkes Groves
        > VCG auctions are a form of second-price auction (sometimes called Vickrey auctions) extended to the multiunit domain. They require a sealed bidding process to incentivize participants to bid their best price.

### Auction Configuration

Auctions (and auction types) will have different configuration options. This will include:

-   Auction owner
-   Auction type
-   Starting time
-   Duration
-   Payout token
-   Quote token
-   Purchase hook addresses
-   Optional allowlist of allowed bidders
    - The allowlist is a contract that supports two approaches:
        - Determining if a user address is allowed, in general
        - Determining if a user address is allowed for a specific auction lot
-   Capacity (in quote or payout token)
-   Optional derivative type and parameters
-   Optional condenser type (used to manipulate auction output for the derivative module)

Auction modules may have additional configuration options, too.

### Payout Types

Payout

-   If an auction has a payout configured (or has a lack of a derivative type), the payout token will be transferred to the bidder at the time of settlement

Derivative

-   If an auction has a derivative type configured, the derivative token will be minted and transferred to the bidder at the time of settlement
-   Structured as an ERC6909, but can be optionally wrapped as an ERC20
    -   Needed because there may be many different derivatives from a single auction. For example, a long-running auction with a fixed-term derivative type would have numerous derivative tokens, each with different expiry dates.
    -   More gas efficient, enabling giving receipt tokens.
-   Actions that can be performed on a derivative token by a token holder/bidder:
    -   Redeem: when the conditions are fulfilled, redeems/cashes in the derivative tokens for the payout token
    -   Exercise: TODO how is this different to redeem?
    -   Wrap: wraps the derivative token into an ERC20
    -   Unwrap: unwraps the derivative token back into the underlying ERC6909
-   Actions that can be performed on a derivative token by the auction owner:
    -   Deploy: deploys a new derivative token
    -   Mint: mints an amount of the derivative token
    -   Reclaim: enables an auction owner to reclaim the payout tokens that have not been redeemed
    -   Transform: transfers the derivative into another form
        -   e.g. transform a vesting token into an option token and creates an auction for it.
-   There are a number of different derivative types:
    -   Fixed expiry
        -   Expires on a specific date
    -   Fixed term
        -   Expires after a specific term, e.g. 3 months
    -   Vesting
        -   Cliff vesting
            -   At a certain expiration date, the full amount is vested
            -   Different users can have different cliff dates (hence it requires ERC6909)
        -   Linear vesting
        -   Rage vesting
            > Rage Vesting introduces the concept of Rage Quitting, where users can unlock their proportional share of tokens vested at a point in time but forfeit the remaining balance.
        -   Staked vesting
        -   Dynamic
            -   Could implement an arbitrary vesting algorithm
    -   Call options
        -   Call options give buyers the opportunity to buy an asset at a specified price within a specific time period
        -   Only covered calls are supported: the auction owner has to provide the collateral so that call options are guaranteed to settle if they are exercised
        -   TODO fixed vs oracle strike
    -   Success token
        -   See [Outcome Finance](https://docs.outcome.finance/success-tokens/what-are-success-tokens)
        -   Combination of a vesting token and an option for those tokens

### Hooks

Hooks are an expansion of the callback function in Bond Protocol V1, modelled after Uniswap V4 hooks.

The callback function in Bond Protocol V1 offered flexibility to the auction owner. For example:

-   Enables the auction owner to mint tokens upon purchase
-   Quote tokens also sent to the callback to give owner flexibility of where to send them.

Hooks in the V2 protocol provide further flexibility and customisation for the auction owner. For example:

-   Custom logic at other places in the transaction, such as before payment, between payment and payout, after payout, settlement

Unlike in V1, hooks will not be gated.

Security risks:

-   There are inherent security risks in running arbitrary code
-   There will be a need to check balances to ensure that after each step (or at the end), invariants are not broken

### Fees

#### V1

-   Purchase
-   Protocol fee (to BP treasury)
-   Referrer fee (for frontends to claim later)
-   Fee variables can be set at any time
-   Option teller has fee on exercise of the option
-   Has slippage check that would mitigate against fees being changed before a bid

#### V2

Principles:

-   Fees are taken in the quote token.
-   The protocol should only take a fee when value is being produced for both parties
-   Don't take fees on basic actions, e.g. redemption and cliff vesting
-   Referrer fees should carry over
-   TODO decide if fees are locked at the time of auction creation
    -   If not locked, a governance action could dramatically alter the fees for open auctions and derivatives

Fees can be taken by the protocol at the following points:

-   Auction creation
    -   e.g. service fee not contingent on volume
-   Atomic auction purchase
-   Batch auction settlement
-   Exercising of derivative token
    -   e.g. early exercising of vesting token, take a cut of residual collateral
    -   would make sense when there's a profit for the bidder

### Module Management

-   Module references
    -   A module is referred to by a `Keycode`, which is an identifier stored as 5 bytes
    -   Specific module versions are referred to by a `Veecode`, which is the version and the `Keycode` identifier
    -   The first 2 bytes are the module version (e.g. "12), followed by 5 bytes for the module name (e.g. "TEST")
    -   For example, `12TEST` would refer to version 12 of the `TEST` module
-   When a new record is created:
    -   The calling contract will have a `Keycode` referring to the desired module type
    -   The `Keycode` will be used to get the `Veecode` of the latest version
    -   The record will reference the `Veecode`, so that subsequent usage will be tied to that implementation

## Design Principles

-   The architecture should be modular, enabling support for different types of auction and derivatives
-   Only handle at the auction-level (e.g. `AuctionHouse`) what needs to be done there
    -   This means that at least initially, there won't be pass-through functions to auction and derivative modules
    -   The reasoning for this is that different auction and derivative types may have different functions and arguments,
        and catering for those in the `AuctionHouse` core contract will increase complexity
    -   For example, it makes the most sense for quote and payout token transfers to be performed at the level of `AuctionHouse`,
        while derivative token transfers be handled in the respective derivative module (due to potential variations in behaviour and conditions)\
    -   Data should also be stored in a similar manner
-   Third-parties will mainly interact with the auction and derivative modules

## Security Considerations

-   The goal is for the protocol to be permissionless and community-owned, which alters the security considerations
-   The functions that solvers interact with (for off-chain computation and/or bid storage) will need to be permissioned
    -   This would likely that the form of a whitelist of addresses that can call the function
-   Auctions should only be administered by the owner

vesting token: collateral is the underlying asset that the bidder will receive after vesting is complete
call option: needs to be a "covered call", meaning that the collateral needs to be provided ahead of time
