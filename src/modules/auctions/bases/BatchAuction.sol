/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

// import "src/modules/Auction.sol";

// // Spec
// // - Allow issuers to create batch auctions to sell a payout token (or a derivative of it) for a quote token
// // - Purchasers will submit orders off-chain that will be batched and submitted at the end of the auction by a Teller. All Tellers should be able to execute batches of orders?
// // - The issuer will provide all relevant information for the running of the batch auction to this contract. Some parameters for derivatives of the payout will be passed onto and processed by the Teller.
// // - The issuer should be able to auction different variables in the purchase.
// //   I need to determine if this should be handled by different batch auctioneers.
// // - There are some overlap with the variables used in Live Auctions, so those should be abstracted and inherited so we don't repeat ourselves.
// // - Data needed for a batch auction:
// //    - capacity - amount of tokens being sold (or bought?)
// //    - quote token
// //    - payout token
// //    - teller
// //    - teller params
// //    - duration (start & conclusion)
// //    - allowlist
// //    - amount sold & amount purchased - do we need to track this since it is just for historical purposes? can we emit the data in an event?
// //    - minimum value to settle auction - minimum value for whatever parameter is being auctioned.
// //      need to think if we need to have a maximum value option, but it can probably just use an inverse.
// //    - info to tell the teller what the auctioned value is and how to settle the auction. need to think on this more

// abstract contract BatchAuction {
//     error BatchAuction_NotConcluded();

//     // ========== STATE VARIABLES ========== //

//     mapping(uint256 lotId => Auction.Bid[] bids) public lotBids;

//     // ========== AUCTION INFORMATION ========== //

//     // TODO add batch auction specific getters
// }

// abstract contract OnChainBatchAuctionModule is AuctionModule, BatchAuction {

//     function bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_) external override onlyParent {
//         // TODO
//         // Validate inputs

//         // Execute user approval if provided?

//         // Call implementation specific bid logic

//         // Store bid data
//     }

//     function settle(uint256 id_) external override onlyParent returns (uint256[] memory amountsOut) {
//         // TODO
//         // Validate inputs

//         // Call implementation specific settle logic

//         // Store settle data
//     }

//     function settle(uint256 id_, Auction.Bid[] memory bids_) external override onlyParent returns (uint256[] memory amountsOut) {
//         revert Auction_NotImplemented();
//     }
// }

// abstract contract OffChainBatchAuctionModule is AuctionModule, BatchAuction {

//     // ========== AUCTION EXECUTION ========== //

//     function bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_) external override onlyParent {
//         revert Auction_NotImplemented();
//     }

//     function settle(uint256 id_) external override onlyParent returns (uint256[] memory amountsOut) {
//         revert Auction_NotImplemented();
//     }

//     /// @notice Settle a batch auction with the provided bids
//     function settle(uint256 id_, Bid[] memory bids_) external override onlyParent returns (uint256[] memory amountsOut) {
//         Lot storage lot = lotData[id_];

//         // Must be past the conclusion time to settle
//         if (uint48(block.timestamp) < lotData[id_].conclusion) revert BatchAuction_NotConcluded();

//         // Bids must not be greater than the capacity
//         uint256 len = bids_.length;
//         uint256 sum;
//         if (lot.capacityInQuote) {
//             for (uint256 i; i < len; i++) {
//                 sum += bids_[i].amount;
//             }
//             if (sum > lot.capacity) revert Auction_NotEnoughCapacity();
//         } else {
//             for (uint256 i; i < len; i++) {
//                 sum += bids_[i].minAmountOut;
//             }
//             if (sum > lot.capacity) revert Auction_NotEnoughCapacity();
//         }

//         // TODO other generic validation?
//         // Check approvals in the Auctioneer since it handles token transfers

//         // Get amounts out from implementation-specific auction logic
//         amountsOut = _settle(id_, bids_);
//     }

//     function _settle(uint256 id_, Bid[] memory bids_) internal virtual returns (uint256[] memory amountsOut);

// }
