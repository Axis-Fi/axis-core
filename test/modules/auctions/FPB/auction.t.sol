// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbCreateAuctionTest is FpbTest {
// [ ] when the caller is not the parent
//  [ ] it reverts
// [ ] when the start time is in the past
//  [ ] it reverts
// [ ] when the duration is less than the minimum
//  [ ] it reverts
// [ ] when the minimum price is 0
//  [ ] it reverts
// [ ] when the minimum fill percentage is > 100%
//  [ ] it reverts
// [ ] when the start time is 0
//  [ ] it sets it to the current block timestamp
// [ ] it sets the price and minFilled
}
