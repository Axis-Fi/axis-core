// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModuleClaimProceedsTest is EmpaModuleTest {
// [ ] when the lot id is invalid
//  [ ] it reverts
// [ ] when the lot is not settled
//  [ ] it reverts
// [ ] it updates the auction status to claimed, and returns the required information
}
