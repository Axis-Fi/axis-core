// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbRefundBidTest is FpbTest {
// [ ] when the caller is not the parent
//  [ ] it reverts
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when the bid id is invalid
//  [ ] it reverts
// [ ] when the caller is not the bid owner
//  [ ] it reverts
// [ ] given the bid has been refunded
//  [ ] it reverts
// [ ] given the lot has concluded
//  [ ] it reverts
// [ ] given the lot has been cancelled
//  [ ] it reverts
// [ ] given the lot has been aborted
//  [ ] it reverts
// [ ] given the lot has been settled
//  [ ] it reverts
// [ ] given the lot is in the settlement period
//  [ ] it reverts
// [ ] it returns the refund amount and updates the bid status
}
