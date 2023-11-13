/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Auctioneer} from "src/policies/auctioneers/bases/Auctioneer.sol";

contract BatchAuctioneer is Auctioneer {
    // Spec
    // - Allow issuers to create batch auctions to sell a payout token (or a derivative of it) for a quote token
    // - Purchasers will submit orders off-chain that will be batched and submitted at the end of the auction by a Teller. All Tellers should be able to execute batches of orders?
    // - The issuer will provide all relevant information for the running of the batch auction to this contract. Some parameters for derivatives of the payout will be passed onto and processed by the Teller.
    // - The issuer should be able to auction different variables in the purchase.
    //   I need to determine if this should be handled by different batch auctioneers.
    // - There are some overlap with the variables used in Live Auctions, so those should be abstracted and inherited so we don't repeat ourselves.
    // - Data needed for a batch auction:
    //    - capacity - amount of tokens being sold (or bought?)
    //    - quote token
    //    - payout token
    //    - teller
    //    - teller params
    //    - duration (start & conclusion)
    //    - allowlist
    //    - amount sold & amount purchased - do we need to track this since it is just for historical purposes? can we emit the data in an event?
    //    - minimum value to settle auction - minimum value for whatever parameter is being auctioned. 
    //      need to think if we need to have a maximum value option, but it can probably just use an inverse.
    //    - info to tell the teller what the auctioned value is and how to settle the auction. need to think on this more

}
