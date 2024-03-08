## Marginal Price Settle Logic

### Terms
- Capacity - total amount of base tokens offered for sale
- Minimum Fill - minimum amount of base tokens that must be sold to settle auction
- Minimum Price - minimum amount of quote tokens per base token that must be received to settle auction
- Total Amount In - total amount of quote tokens received on auction settlement
- Total Amount Out - total amount of base tokens paid on auction settlement
- Marginal Bid ID - the last bid ID that settles at a given marginal price. if the marginal price is in between bids, then this will be zero.

### Goals
1. Fill as much of the capacity as possible with valid bids (above minimum price and minimum size)
2. Check for intermediate marginal prices that fill total capacity between bids to avoid large cliffs.
3. If not able to fill total capacity, try to settle the auction at the minimum price with a portion of the capacity (must be greater than the minimum fill).

### Mechanism

Note: We assume that bid IDs are indexed from 1 such that all bid IDs are non-zero.

1. Sort bids by price (high to low), then by order submitted (low to high). In EMPAM, bids are pre-sorted during decryption.
2. Iterate through the bids to find the ones that settle the auction to find: marginal price, marginal bid ID, partial fill ID, totalAmountIn, totalAmountOut
    - If current bid price < minimum price, we have seen all valid bids and weren't able to settle at last price. Check if the auction can be filled at the minimum price. If so, calculate the intermediate marginal price that fills the capacity (>= minimumPrice). If not, the minimum price is the marginal price. Set marginal bid ID to zero since no bids were submitted at the marginal price. Exit loop. Otherwise, continue.
    - Before considering the current bid, check if we can fill total capacity from previously considered bids at current bid price. If so, calculate the intermediate marginal price that fills the auction (>= currentPrice) and set marginalBidId to zero, which means no bids at the current price are included. Exit loop. Otherwise, continue.
    - Current bid is now considered. Increment totalAmountIn with current bid amount. Calculate totalAmountOut from totalAmountIn at currentPrice. If totalAmountOut is enough to fill capacity, then the marginal price is the current bid price. If totalAmountOut is strictly greater than capacity, then current bid is a partial fill. Set the marginal bid ID to the current bid ID. Exit loop. Otherwise, continue.
    - If this is the last bid in the queue, we have seen all valid bids and weren't able to settle at current price. Check if the auction can be filled at the minimum price. If so, calculate the intermediate marginal price that fills the capacity (>= minimumPrice). If not, the minimum price is the marginal price. Set marginal bid ID to zero since no bids were submitted at the marginal price.

3. Determine if Auction can be Settled:
    - If marginalPrice >= minimumPrice and totalAmountOut >= minimumFilled, then we can settle the auction. Save marginal price and marginal bid ID in storage. If partial bid ID is not zero, claim it now so we don't have to deal with it later. Send proceeds and refund (if any) to seller.
    - Otherwise, the auction cannot be settled. Save marginal price to a value greater than the highest bid price in storage so that all bids are refunded. Send refund to seller.







