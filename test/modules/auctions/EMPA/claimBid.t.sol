// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleClaimBidTest is EmpaModuleTest {
    // [ ] when the lot id is invalid
    //  [ ] it reverts
    // [ ] when the bid id is invalid
    //  [ ] it reverts
    // [ ] when the bidder is not the the bid owner
    //  [ ] it reverts
    // [ ] given the bid has already been claimed
    //  [ ] it reverts
    // [ ] given the lot is not settled
    //  [ ] it reverts
    // [ ] when the caller is not the parent
    //  [ ] it reverts
    // [ ] given the minAmountOut is 0
    //  [ ] it refunds the bid
    // [ ] it refunds the exact bid amount
    // [ ] it sends the payout
}
