// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract ClaimCuratorProceedsTest is AuctionHouseTest {
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when the auction has not concluded
//  [ ] it reverts
// [ ] when the auction module reverts
//  [ ] it reverts
// [ ] when the curator fee is zero
//  [ ] it does not transfer any funds
// [ ] given the capacity is not filled
//  [ ] it calculates the curator payout based on the utilised capacity
// [ ] given the seller has claimed proceeds
//  [ ] given the bidders have claimed proceeds
//   [ ] it calculates the curator payout based on the remaining capacity
//  [ ] it calculates the curator payout based on the remaining capacity
// [ ] given the bidders have claimed proceeds
//  [ ] it calculates the curator payout based on the remaining capacity
// [ ] when the caller is not the curator
//  [ ] it transfers to the curator
// [ ] when the caller is the curator
//  [ ] it transfers to the curator
}
