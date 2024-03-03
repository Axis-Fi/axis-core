// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleSubmitPrivateKeyTest is EmpaModuleTest {
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when the lot is active
//  [ ] it reverts
// [ ] when the lot has not started
//  [ ] it reverts
// [ ] given the private key has already been submitted
//  [ ] it reverts
// [ ] when the public key is not derived from the private key
//  [ ] it reverts
// [ ] when the caller is not the parent
//  [ ] it succeeds
// [ ] it sets the private key and decodes the bids
}
