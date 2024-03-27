
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";

contract UniswapV3DirectToLiquidityOnCancelTest is UniswapV3DirectToLiquidityTest {

    // ============ Tests ============ //

    // [ ] when the onCreate permission is missing
    //  [ ] it reverts
    // [ ] when the onCancel permission is missing
    //  [ ] it reverts
    // [ ] when the onCurate permission is missing
    //  [ ] it reverts
    // [ ] when the onClaimProceeds permission is missing
    //  [ ] it reverts
    // [ ] when the receiveQuoteTokens permission is missing
    //  [ ] it reverts
    // [ ] when the sendBaseTokens permission is present
    //  [ ] it reverts
    // [ ] when the Uniswap V3 Factory parameter is address 0
    //  [ ] it reverts
    // [ ] when the G-UNI Factory parameter is address 0
    //  [ ] it reverts

}