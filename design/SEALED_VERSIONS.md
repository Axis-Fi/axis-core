# Sealed Bid Auction Development

## Context

Bond Protocol, rebranding to Axis, is changing directions from our current "atomic" auction products to focus on developing and deploying a Sealed Bid Batch Auction product. The primary expected use cases are token sales and issuing token derivatives. We believe a decentralized sealed bid batch auction can allow for superior price discovery and outcomes for teams over current market solutions.

## Design

### Base Auction Flow
There are three main steps to any batch auction:
1. Bid submission - Users submit bids over an alloted time period
2. Evaluation - The submitted bids are evaluated using the auction logic and winners are determined
3. Settlement - The proceeds of the auction are distributed to the winners and the auction is closed

It's important to note that any of these three steps can be performed on-chain or off-chain.

### Auction Fairness
An auction system must assure users of inclusion and fair treatment of their bids. Specifically, it needs to provide guarantees around:
1. Completeness - All bids that are submitted are evaluated
2. Accuracy - The evaluation of bids is performed correctly

Depending on the design of the system, these properties may be inherent or difficult to achieve. There is typically a tradeoff between UX/efficiency and these guarantees.

### Types of Batch Auctions
There are four main types of batch auctions that could be built based on where the bids are submitted and where the bid evaluation logic is performed. We will refer to these as "local", for on-chain, and "external", for off-chain, to avoid using similar hyphenated words. Settlement is assumed to be on-chain.
1. Local (aka on-chain) bid submission and evaluation
Fully on-chain auction, similar to Gnosis auction, but with encryption. Since you cannot pre-sort the bids, it requires an intermediate step to decrypt and sort all submitted bids before settlement to avoid issues with the gas limit. The risk of DoS attacks is decreased by requiring bid deposits, but this leaks some information. This solution natively guarantees both "completeness" and "accuracy" of the bids.

2. External bid submission and local evaluation

Bids are collected off-chain, filtered for bids that aren't valid (e.g. below min price or too small), sorted, and submitted on-chain, where the auction price logic is performed to determine the winners. This version natively adheres to the "accuracy" guarantee through on-chain evaluation of bids, but requires trusting the "completeness" property of the bids that are submitted for evaluation. This is difficult to do in a decentralized way.

3. Local submission and external evaluation

Bids are submitted on-chain (encrypted). Once the auction ends, an external party can decrypt the bid data, perform bid evaluation off-chain, and submit the winning bids with a validity proof of the evaluation. This version natively adheres to the "completness" property, but requires trusting the "accuracy" of the submitted evaluation. A validity proof can provide this in a decentralized way. This may be a workable solution if a ZK proof could be constructed correctly to verify the off-chain evaluation. Currently, we are running into issues with the size of the required circuit(s). More information on this below.

4. External bid submission and evaluation
Bids are collected off-chain and the settlement algorithm is performed to determine the winning bids. the winning bids are submitted on-chain for settlement of payments. This would have the best UX and is most gas efficient, but is the least decentralized. It requires trusting both the "completeness" and "accuracy" of the submitted evaluation.

There is also a fifth option where Settlement is also performed externally and proved locally, which equates to a validium, but that isn't considered in detail here.

There are many potential product designs that we have considered. Each has tradeoffs along a few major dimensions:
- Decentralization
- User Experience
- Level of privacy 
- Efficiency (i.e. gas costs)

