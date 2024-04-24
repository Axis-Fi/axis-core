// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";

contract SqrtPriceMathTest is Test {
    address internal constant TOKEN0 = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address internal constant TOKEN1 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // From OHM-WETH pool
    // Token id: 562564
    // https://revert.finance/#/account/0x245cc372C84B3645Bf0Ffe6538620B04a217988B (for current amounts)
    // https://etherscan.io/address/0x88051b0eea095007d3bef21ab287be961f3d8598#readContract#F11 (for sqrtPriceX96)
    uint256 internal constant AMOUNT0 = 185_339_349_000_000;
    uint256 internal constant AMOUNT1 = 647_257_004_000_000_000_000;
    uint160 internal constant SQRTPRICEX96_ACTUAL = 148_058_773_132_005_407_513_152_397_312_640;
    uint160 internal constant SQRTPRICEX96 = 148_058_773_168_959_257_235_299_580_805_548;
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
    }

    function test_whenTokenAIsToken1() public {
        uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(TOKEN1, TOKEN0, AMOUNT1, AMOUNT0);
        assertEq(sqrtPriceX96, SQRTPRICEX96, "SqrtPriceX96");
    }
}
