// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";

import {TickMath} from "uniswap-v3-core/libraries/TickMath.sol";

import {console2} from "forge-std/console2.sol";

contract SqrtPriceMathTest is Test {
    address internal constant TOKEN0 = address(0x1);
    address internal constant TOKEN1 = address(0x2);

    // From OHM-WETH pool
    // Token id: 562564
    // https://revert.finance/#/account/0x245cc372C84B3645Bf0Ffe6538620B04a217988B (for current amounts)
    // https://etherscan.io/address/0x88051b0eea095007d3bef21ab287be961f3d8598#readContract#F11 (for sqrtPriceX96)
    uint256 internal constant AMOUNT0 = 647_257_004_000_000_000_000; // OHM
    uint256 internal constant AMOUNT1 = 185_339_349_000_000_000_000_000; // WETH
    uint160 internal constant SQRTPRICEX96 = 148_058_773_132_005_407_513_152_397_312_640;
    // sqrt((647.257004*1e18)/(185339.349*1e9))*2**96 ~= 148058773132005407513152397312640

    // [X] when tokenA is token0
    //  [X] it calculates the correct sqrtPriceX96
    // [X] when tokenA is token1
    //  [X] it calculates the correct sqrtPriceX96
    // [X] when tokenA decimals is greater than tokenB decimals
    //  [X] it calculates the correct sqrtPriceX96
    // [X] when tokenA decimals is less than tokenB decimals
    //  [X] it calculates the correct sqrtPriceX96

    function test_whenTokenAIsToken0() public {
        uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(TOKEN0, TOKEN1, AMOUNT0, AMOUNT1);
        assertEq(sqrtPriceX96, SQRTPRICEX96, "SqrtPriceX96");

        console2.log("ratio", TickMath.getSqrtRatioAtTick(-81_152));
    }

    function test_whenTokenAIsToken1() public {
        uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(TOKEN1, TOKEN0, AMOUNT1, AMOUNT0);
        assertEq(sqrtPriceX96, SQRTPRICEX96, "SqrtPriceX96");
    }
}
