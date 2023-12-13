# Bond Protocol - V2 Features

## Terminology

Lot

- _What_ is being sold
- A token or group of tokens that are available for bidding through an auction
- The current design supports a single lot per auction

Auction

- The auction (specifically the type) specifies _how_ the lot is being sold

Market

- This term was used in the V1 protocol
- `Auction` is a more expansive term that encompasses the functionality in the V2 protocol

Quote Token

- The token that is offered by the bidder in return for the payout token

Payout Token

- The token that is provided to the bidder as a payment for the quote token
- A payout token is used when the payout is non-vesting, where the payout token is transferred at the time of auction settlement

Derivative Token

- A form of a payout token that is used when the payout vests over time

### Actions

Purchase

- _Immediately_ buy tokens from an auction
- Provided the auction is open and the purchase amount is within capacity, the purchase will succeed
- Valid only for atomic auctions (since batch auctions are settled later)

Bid

- An offer to buy tokens from an auction
- The success of the bid is not known until the auction is settled
- Valid only for batch auctions (since atomic auctions are settled at the same time)

Settle

- Finalises the bids for an auction
- Valid only for batch auctions (since atomic auctions are settled at the same time)

Close

- Ends the auction immediately/prematurely
- Further capacity cannot be sold nor bids/purchases accepted
- Valid for all auction types
- In the case of a batch auction, the auction will not be settled

## Features

### Flexibility in Storage and Computation

Bond Protocol V1 required bids to be stored on-chain and auctions to be settled on-chain. Not all auction types are suited to this.

For this reason, V2 supports off-chain bids and settlement computation. This enables auctions that were not possible earlier:

- sealed bid auctions
- providing Bond Protocol auctions as a liquidity source for CoW Protocol
- off-chain computation of auction settlement by solvers

TODO what else can be done off-chain?

TODO can the settlement be performed off-chain and the accepted bids be passed to the AuctionHouse or auction module?

### Auction Types

Atomic

- Atomic auctions are settled at the time of purchase
- Settled immediately: offered tokens are transferred at time of purchase

Batch

- Two major types:
    - Open
        - Bids are recorded on-chain
    - Sealed
        - Bids are recorded off-chain and submitted on-chain at the time of settlement
        - The submission function will be permissioned in order to restrict who can submit the set of sealed bids
        - This auction type prevents other bidders from seeing active bids
- Quote tokens are only transferred at the time of settlement
    - This avoids having to provide functionality for bidders to claim a refund of their quote tokens
- Payout tokens are transferred at the time of settlement

### Auction Configuration

Auctions (and auction types) will have different configuration options. This will include:

- Auction owner
- Auction type
- Starting time
- Duration
- Payout token
- Quote token
- Purchase hook addresses
- Optional whitelist of allowed bidders
- Capacity (in quote or payout token)
- Optional derivative type and parameters
- Optional condenser type (used to manipulate auction output for the derivative module)

Auction modules may have additional configuration options, too.

### Payout Types

Payout

- If an auction has a payout configured (or has a lack of a derivative type), the payout token will be transferred to the bidder at the time of settlement

Derivative

- If an auction has a derivative type configured, the derivative token will be minted and transferred to the bidder at the time of settlement
- Structured as an ERC6909, but can be optionally wrapped as an ERC20
    - TODO why ERC6909?
- Actions that can be performed on a derivative token by a token holder/bidder:
    - Redeem: when the conditions are fulfilled, redeems/cashes in the derivative tokens for the payout token
    - Exercise: TODO how is this different to redeem?
    - Wrap: wraps the derivative token into an ERC20
    - Unwrap: unwraps the derivative token back into the underlying ERC6909
- Actions that can be performed on a derivative token by the auction owner:
    - Deploy: deploys a new derivative token
    - Mint: mints an amount of the derivative token
    - Reclaim: enables an auction owner to reclaim the payout tokens that have not been redeemed
    - Transform: transfers the derivative into another form
        - TODO examples
- A derivative token can have a number of uses:
    - Cliff vesting
        - At a certain expiration date, the full amount is vested
    - Success token
        - See [Outcome Finance](https://docs.outcome.finance/success-tokens/what-are-success-tokens)
    - Options
    - Rage Vesting
    - TODO complete list of uses

### Hooks

TODO purchase hooks

### Fees

Fees can be taken by the protocol at the following points:

- Auction creation?
- Bid/purchase
- Settlement?
- Redemption of derivative token

TODO are fees locked at the time of auction creation, or can they be modified after?

TODO any support for referrers? (see Olympus Cooler Loans discussion for distributed frontends)

## Design Principles

- The architecture should be modular, enabling support for different types of auction and derivatives
- Only handle at the auction-level (e.g. `AuctionHouse`) what needs to be done there
    - This means that at least initially, there won't be pass-through functions to auction and derivative modules
    - The reasoning for this is that different auction and derivative types may have different functions and arguments,
    and catering for those in the `AuctionHouse` core contract will increase complexity
    - For example, it makes the most sense for quote and payout token transfers to be performed at the level of `AuctionHouse`,
    while derivative token transfers be handled in the respective derivative module (due to potential variations in behaviour and conditions)
- Third-parties will mainly interact with the auction and derivative modules

## Security Considerations

- The goal is for the protocol to be permissionless and community-owned, which alters the security considerations
- The functions that solvers interact with (for off-chain computation and/or bid storage) will need to be permissioned
    - This would likely that the form of a whitelist of addresses that can call the function
- Auctions should only be administered by the owner
