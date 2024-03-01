// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleRefundBidTest is EmpaModuleTest {

    // [ ] when the lot id is invalid
    //  [ ] it reverts
    // [ ] when the bid id is invalid
    //  [ ] it reverts
    // [ ] when the bidder is not the the bid owner
    //  [ ] it reverts
    // [ ] given the bid has already been refunded
    //  [ ] it reverts
    // [ ] given the lot is concluded
    //  [ ] it reverts
    // [ ] when the caller is not the parent
    //  [ ] it reverts
    // [ ] it refunds the bid amount and updates the bid status
    // [ ] it refunds the exact bid amount
}
