# Bond Protocol - V2 Features

## Terminology

Auction

- Sale offering for tokens

Lot

- A token or group of tokens that are available for bidding through an auction
- TODO can an auction have multiple, differing lots?

Market

- This term was used in the V1 protocol
- `Auction` is a more expansive term that encompasses the functionality in the V2 protocol

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

On-chain vs off-chain

Atomic

- Transfer at time of purchase

Batch

- Two versions: one for on-chain auctions where the contract already has all the bids, and another where the bids have to be supplied on settlement (for sealed bid auctions). In the latter case, it will need to be permissioned because the bids submitted must be trusted.
- Transfer at time of settlement


Sealed Batch
