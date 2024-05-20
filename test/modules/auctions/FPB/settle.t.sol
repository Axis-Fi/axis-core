// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbSettleTest is FpbTest {
// [ ] when the caller is not the parent
//  [ ] it reverts
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when the lot has not concluded
//  [ ] it reverts
// [ ] when the lot has been cancelled
//  [ ] it reverts
// [ ] when the lot has been aborted
//  [ ] it reverts
// [ ] when the lot has been settled
//  [ ] it reverts
// [ ] when the lot is in the settlement period
//  [ ] it settles
// [ ] when the settlement period has passed
//  [ ] it settles
// [ ] when the filled capacity is below the minimum
//  [ ] it marks the settlement as not cleared and updates the status
// [ ] it marks the settlement as cleared, updates the status and returns the total in and out
}
