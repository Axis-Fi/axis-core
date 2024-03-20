// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

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
        // Needs to be verified. Does it need to handle token decimal differences?
        uint256 numerator = amount1 << 192;
        uint256 denominator = amount0;
        uint256 ratioX192 = (numerator / denominator);
        uint256 sqrtPriceX96Temp = FixedPointMathLib.sqrt(ratioX192);

        // TODO determine if this is the correct course of action - it would brick claiming proceeds
        if (sqrtPriceX96Temp > type(uint160).max) revert("overflow");

        sqrtPriceX96 = uint160(sqrtPriceX96Temp);
    }
}
