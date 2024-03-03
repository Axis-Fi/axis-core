// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleSettleTest is EmpaModuleTest {
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when the lot has not concluded
//   [ ] it reverts
// [ ] when the lot has not been decrypted
//   [ ] it reverts
// [ ] when the lot has been settled already
//   [ ] it reverts
// [ ] when the marginal price overflows
//  [ ] it reverts

// [ ] when the filled amount is less than the lot minimum
//  [ ] it returns no amounts in and out, and no partial fill
// [ ] when the marginal price is less than the minimum price
//  [ ] it returns no amounts in and out, and no partial fill
// [ ] given the filled capacity is greater than the lot minimum
//  [ ] it returns the amounts in and out, and no partial fill
// [ ] given some of the bids fall below the minimum price
//  [ ] it returns the amounts in and out, excluding those below the minimum price, and no partial fill
// [ ] given the lot is over-subscribed with a partial fill
//  [ ] it returns the amounts in and out, with the marginal price is the price at which the lot capacity is exhausted, and a partial fill for the lowest winning bid
// [ ] given that the quote token decimals are larger than the base token decimals
//  [ ] it succeeds
// [ ] given that the quote token decimals are smaller than the base token decimals
//  [ ] it succeeds

// [ ] given that a bid's price results in a uint96 overflow
//  [ ] the settle function does not revert
// [ ] given the expended capacity results in a uint96 overflow
//  [ ] the settle function does not revert
}
