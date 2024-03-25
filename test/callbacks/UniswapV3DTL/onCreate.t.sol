// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

contract UniswapV3DirectToLiquidityOnCreateTest is UniswapV3DirectToLiquidityTest {
    // [ ] when the lot has already been registered
    //  [ ] it reverts
    // [ ] when the proceeds utilisation is 0
    //  [ ] it reverts
    // [ ] when the proceeds utilisation is greater than 100%
    //  [ ] it reverts
    // [ ] when the pool fee is greater than the maximum fee
    //  [ ] it reverts
    // [ ] given the pool fee is not enabled
    //  [ ] it reverts
    // [ ] given uniswap v3 pool already exists
    //  [ ] it reverts
    // [ ] when the start and expiry timestamps are the same
    //  [ ] it reverts
    // [ ] when the start timestamp is after the expiry timestamp
    //  [ ] it reverts
    // [ ] when the start timestamp is before the current timestamp
    //  [ ] it succeeds
    // [ ] when the expiry timestamp is before the current timestamp
    //  [ ] it reverts
    // [ ] given the linear vesting module is not installed
    //  [ ] it reverts
    // [ ] given the send base tokens flag is enabled
    //  [ ] given the seller has an insufficient balance
    //   [ ] it reverts
    //  [ ] given the seller has an insufficient allowance
    //   [ ] it reverts
    //  [ ] it registers the lot, transfers the base tokens to the auction house
    // [ ] it registers the lot
}