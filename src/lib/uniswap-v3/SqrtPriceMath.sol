// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {console2} from "forge-std/console2.sol";

library SqrtPriceMath {
    function getSqrtPriceX96(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external pure returns (uint160 sqrtPriceX96) {
        (uint256 amount0, uint256 amount1) =
            tokenA < tokenB ? (amountA, amountB) : (amountB, amountA);

        // Source: https://github.com/Uniswap/v3-sdk/blob/2c8aa3a653831c6b9e842e810f5394a5b5ed937f/src/utils/encodeSqrtRatioX96.ts
        // SqrtPriceX96 = sqrt(amount1/amount0) * 2^96
        //              = sqrt(amount1 * 2^192 / amount0)

        // This seems to be truncating 185339349000000000000000 * 2^192 from the expected value of 1.1633939492e81 to 30828676021860619530268216106975167770139507879063629246398176496786507563008 (3.0828676022e76)
        uint256 numerator = amount1 << 192;
        console2.log("numerator", numerator);
        uint256 denominator = amount0;
        console2.log("denominator", denominator);
        uint256 ratioX192 = (numerator / denominator) << 64;
        console2.log("ratioX192", ratioX192);
        uint256 sqrtPriceX96Temp = FixedPointMathLib.sqrt(ratioX192);

        // TODO determine if this is the correct course of action - it would brick claiming proceeds
        if (sqrtPriceX96Temp > type(uint160).max) revert("overflow");

        sqrtPriceX96 = uint160(sqrtPriceX96Temp);
    }
}
