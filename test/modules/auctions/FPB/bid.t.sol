// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbBidTest is FpbTest {
// [ ] when the caller is not the parent
//  [ ] it reverts
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when the lot has not started
//  [ ] it reverts
// [ ] when the lot has concluded
//  [ ] it reverts
// [ ] when the lot has been cancelled
//  [ ] it reverts
// [ ] when the lot has been aborted
//  [ ] it reverts
// [ ] when the lot has been settled
//  [ ] it reverts
// [ ] when the lot is in the settlement period
//  [ ] it reverts
// [ ] when the bid amount is 0
//  [ ] it reverts
// [ ] when the bid amount is greater than uint96 max
//  [ ] it reverts
// [ ] when the bid amount reaches capacity
//  [ ] it records the bid and concludes the auction
// [ ] when the bid amount is greater than the remaining capacity
//  [ ] it records the bid, concludes the auction and calculates partial fill
// [ ] it records the bid
}
