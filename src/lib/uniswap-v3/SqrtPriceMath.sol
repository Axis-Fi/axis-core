// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice     Library to calculate sqrtPriceX96 from token amounts
library SqrtPriceMath {
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    uint160 internal constant MAX_SQRT_RATIO =
        1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    /// @notice     Calculates the sqrtPriceX96 from the token amounts
    /// @dev        The order of the tokens is irrelevant, as the values will be re-ordered.
    ///
    /// @param      tokenA          The address of a token
    /// @param      tokenB          The address of the other token
    /// @param      amountA         The amount of tokenA
    /// @param      amountB         The amount of tokenB
    /// @return     sqrtPriceX96    The sqrtPriceX96
    function getSqrtPriceX96(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal pure returns (uint160 sqrtPriceX96) {
        (uint256 amount0, uint256 amount1) =
            tokenA < tokenB ? (amountA, amountB) : (amountB, amountA);

        // Source: https://github.com/Uniswap/v3-sdk/blob/2c8aa3a653831c6b9e842e810f5394a5b5ed937f/src/utils/encodeSqrtRatioX96.ts
        // SqrtPriceX96 = sqrt(amount1/amount0) * 2^96
        //              = sqrt(amount1 * 2^192 / amount0)

        // Use fullMulDiv to prevent a phantom overflow
        // If amount1 is too high, this will revert
        uint256 ratioX192 = FixedPointMathLib.fullMulDiv(amount1, 2 ** 192, amount0);
        uint256 sqrtPriceX96Temp = FixedPointMathLib.sqrt(ratioX192);

        if (sqrtPriceX96Temp < MIN_SQRT_RATIO) revert("underflow");
        if (sqrtPriceX96Temp > MAX_SQRT_RATIO) revert("overflow");

        sqrtPriceX96 = uint160(sqrtPriceX96Temp);
    }
}
