// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbCancelAuctionTest is FpbTest {
// [ ] when the caller is not the parent
//  [ ] it reverts
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when the auction has concluded
//  [ ] it reverts
// [ ] when the auction has been cancelled
//  [ ] it reverts
// [ ] when the auction has been aborted
//  [ ] it reverts
// [ ] when the auction has been settled
//  [ ] it reverts
// [ ] when the auction has started
//  [ ] it reverts
// [ ] it updates the conclusion, capacity and status
}
