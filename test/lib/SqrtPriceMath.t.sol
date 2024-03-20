// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";

contract SqrtPriceMathTest is Test {

    address internal constant TOKEN0 = address(0x1);
    address internal constant TOKEN1 = address(0x2);

    // From DAI-WETH pool
    uint256 internal constant AMOUNT0 = 3354644702045819714221889; // DAI
    uint256 internal constant AMOUNT1 = 1128870660210923587702; // WETH
    uint160 internal constant SQRTPRICEX96 = 1369947724019237678865797100;

    // [X] when tokenA is token0
    //  [X] it calculates the correct sqrtPriceX96
    // [X] when tokenA is token1
    //  [X] it calculates the correct sqrtPriceX96
    // [ ] when tokenA decimals is greater than tokenB decimals
    //  [ ] it calculates the correct sqrtPriceX96
    // [ ] when tokenA decimals is less than tokenB decimals
    //  [ ] it calculates the correct sqrtPriceX96

    function test_whenTokenAIsToken0() public {
        uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(TOKEN0, TOKEN1, AMOUNT0, AMOUNT1);
        assertEq(sqrtPriceX96, SQRTPRICEX96, "SqrtPriceX96");
    }

    function test_whenTokenAIsToken1() public {
        uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(TOKEN1, TOKEN0, AMOUNT1, AMOUNT0);
        assertEq(sqrtPriceX96, SQRTPRICEX96, "SqrtPriceX96");
    }
}
