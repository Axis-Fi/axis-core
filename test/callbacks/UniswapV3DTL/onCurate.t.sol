// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

contract UniswapV3DirectToLiquidityOnCurateTest is UniswapV3DirectToLiquidityTest {
    // [ ] when the lot has not been registered
    //  [ ] it reverts
    // [ ] given the send base tokens flag is enabled
    //  [ ] given the seller has an insufficient balance
    //   [ ] it reverts
    //  [ ] given the seller has an insufficient allowance
    //   [ ] it reverts
    //  [ ] it transfers the base tokens to the auction house
}
