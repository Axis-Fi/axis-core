// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

import {FpbTest} from "test/modules/auctions/FPB/FPBTest.sol";

contract FpbClaimBidsTest is FpbTest {
// [ ] when the caller is not the parent
//  [ ] it reverts
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when any bid id is invalid
//  [ ] it reverts
// [ ] given the lot has not concluded
//  [ ] it reverts
// [ ] given any bid has been claimed
//  [ ] it reverts
// [ ] given it is during the settlement period
//  [ ] it reverts
// [ ] given the lot is not settled
//  [ ] it reverts
// [ ] given the auction was aborted
//  [ ] it returns the refund amount and updates the bid status
// [ ] given the settlement cleared
//  [ ] given the bid was a partial fill
//   [ ] it returns the payout and refund amounts and updates the bid status
//  [ ] it returns the refund amount and updates the bid status
// [ ] it returns the refund amount and updates the bid status
}
