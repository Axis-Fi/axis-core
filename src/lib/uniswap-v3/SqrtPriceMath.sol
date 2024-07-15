// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";
import {FullMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/FullMath.sol";

/// @notice     Library to calculate sqrtPriceX96 from token amounts
library SqrtPriceMath {
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

        // Use Uniswap's FullMath.mulDiv to prevent a phantom overflow
        uint256 ratioX192 = FullMath.mulDiv(amount1, 2 ** 192, amount0);
        uint256 sqrtPriceX96Temp = FixedPointMathLib.sqrt(ratioX192);

        if (sqrtPriceX96Temp > type(uint160).max) revert("overflow");

        sqrtPriceX96 = uint160(sqrtPriceX96Temp);
    }
}
