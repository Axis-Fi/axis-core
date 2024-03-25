// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

contract UniswapV3DirectToLiquidityOnClaimProceedsTest is UniswapV3DirectToLiquidityTest {
    // [ ] given the pool is created
    //  [ ] it initializes the pool
    // [ ] given the pool is created and initialized
    //  [ ] it succeeds
    // [ ] given minting pool tokens utilises less than the available amount of base tokens
    //  [ ] the excess base tokens are returned
    // [ ] given minting pool tokens utilises less than the available amount of quote tokens
    //  [ ] the excess quote tokens are returned
    // [ ] given the receive quote tokens flag is false
    //  [ ] it transfers the quote tokens from the seller
    // [ ] given the send base tokens flag is false
    //  [ ] it transfers the base tokens from the seller
    // [ ] given the send base tokens flag is true
    //  [ ] when the refund amount is less than the base tokens required
    //   [ ] it transfers the base tokens from the seller
    // [ ] given vesting is enabled
    //  [ ] it mints the vesting tokens to the seller
    // [ ] it creates and initializes the pool, creates a pool token, deposits into the pool token, transfers the LP token to the seller and transfers any excess back to the seller
}
