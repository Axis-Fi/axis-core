// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AuctionModule} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract ClaimBidsTest is AuctionHouseTest {

    // [ ] when the lot id is invalid
    //  [ ] it reverts
    // [ ] when the auction module reverts
    //  [ ] it reverts
    // [ ] when the payout is not set
    //  [ ] it returns the bid amount to the bidder
    // [ ] when the referrer is set
    //  [ ] it sends the payout to the bidder, and allocates fees to the referrer and protocol
    // [ ] it sends the payout to the bidder, and allocates referrer and protocol fees to the protocol
    // [ ] when the protocol fee is changed before claim
    //  [ ] it allocates the cached fee
    // [ ] when the referrer fee is changed before the claim
    //  [ ] it allocates the cached fee

}
