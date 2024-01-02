// /// SPDX-License-Identifier: AGPL-3.0
// pragma solidity 0.8.19;

// import "src/modules/Auction.sol";

// abstract contract AtomicAuction {

//     // ========== AUCTION INFORMATION ========== //

//     function payoutFor(uint256 id_, uint256 amount_) public view virtual returns (uint256);

//     function priceFor(uint256 id_, uint256 payout_) public view virtual returns (uint256);

//     function maxPayout(uint256 id_) public view virtual returns (uint256);

//     function maxAmountAccepted(uint256 id_) public view virtual returns (uint256);
// }

// abstract contract AtomicAuctionModule is AuctionModule, AtomicAuction {

//     // ========== AUCTION EXECUTION ========== //

//     function purchase(uint256 id_, uint256 amount_, bytes calldata auctionData_) external override onlyParent returns (uint256 payout, bytes memory auctionOutput) {
//         Lot storage lot = lotData[id_];

//         // Check if market is live, if not revert
//         if (!isLive(id_)) revert Auction_MarketNotActive();

//         // Get payout from implementation-specific auction logic
//         payout = _purchase(id_, amount_);

//         // Update Capacity

//         // Capacity is either the number of payout tokens that the market can sell
//         // (if capacity in quote is false),
//         //
//         // or the number of quote tokens that the market can buy
//         // (if capacity in quote is true)

//         // If amount/payout is greater than capacity remaining, revert
//         if (lot.capacityInQuote ? amount_ > lot.capacity : payout > lot.capacity)
//             revert Auction_NotEnoughCapacity();
//         // Capacity is decreased by the deposited or paid amount
//         lot.capacity -= lot.capacityInQuote ? amount_ : payout;

//         // Markets keep track of how many quote tokens have been
//         // purchased, and how many payout tokens have been sold
//         lot.purchased += amount_;
//         lot.sold += payout;
//     }

//     /// @dev implementation-specific purchase logic can be inserted by overriding this function
//     function _purchase(
//         uint256 id_,
//         uint256 amount_,
//         uint256 minAmountOut_
//     ) internal virtual returns (uint256);

//     function bid(uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_) external override onlyParent {
//         revert Auction_NotImplemented();
//     }

//     function settle(uint256 id_, Bid[] memory bids_) external override onlyParent returns (uint256[] memory amountsOut) {
//         revert Auction_NotImplemented();
//     }

//     function settle(uint256 id_) external override onlyParent returns (uint256[] memory amountsOut) {
//         revert Auction_NotImplemented();
//     }

//     // ========== AUCTION INFORMATION ========== //

//     // These functions do not include fees. Policies can call these functions with the after-fee amount to get a payout value.
//     // TODO
//     // function payoutFor(uint256 id_, uint256 amount_) public view virtual returns (uint256);

//     // function priceFor(uint256 id_, uint256 payout_) public view virtual returns (uint256);

//     // function maxPayout(uint256 id_) public view virtual returns (uint256);

//     // function maxAmountAccepted(uint256 id_) public view virtual returns (uint256);
// }