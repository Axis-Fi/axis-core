// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

contract UniswapV3DirectToLiquidityOnCancelTest is UniswapV3DirectToLiquidityTest {
    // [ ] when the lot has not been registered
    //  [ ] it reverts
    // [ ] when the send base tokens flag is true
    //  [ ] it marks the lot as inactive, it transfers the base tokens to the seller
    // [ ] it marks the lot as inactive
}