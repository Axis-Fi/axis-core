// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleDecryptBidsTest is EmpaModuleTest {
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] given the lot has not started
//  [ ] it reverts
// [ ] given the lot has not concluded
//  [ ] it reverts
// [ ] given the private key has not been submitted
//  [ ] it reverts
// [ ] when the number of bids to decrypt is larger than the number of bids
//  [ ] it succeeds
// [ ] given a bid cannot be decrypted
//  [ ] it is ignored
// [ ] given a bid amount out is larger than supported
//  [ ] it is ignored
// [ ] when the number of bids to decrypt is smaller than the number of bids
//  [ ] it updates the nextDecryptIndex
// [ ] given a bid amount out is smaller than the minimum bid size
//  [ ] the bid record is updated, but it is not added to the decrypted bids queue
// [ ] given the bids are already decrypted
//  [ ] it reverts
// [ ] when there are no bids to decrypt
//  [ ] the lot is marked as decrypted
// [ ] it decrypts the bids and updates bid records
}
