// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract ClaimProceedsTest is AuctionHouseTest {
// [ ] when the auction is not settled
//  [ ] it reverts
// [ ] given the proceeds have already been claimed
//  [ ] it reverts
// [ ] given it is not a batch auction
//  [ ] it reverts
// [ ] given the auction is not pre-funded
//  [ ] it sends the proceeds to the seller
// [ ] given the auction is pre-funded
//  [ ] given the auction has curation enabled
//   [ ] it sends the proceeds, unused capacity and unused curator fees to the seller
//  [ ] it sends the proceeds and unused capacity to the seller
// [ ] given the auction has hooks enabled
//  [ ] it calls the settle callback
}
