/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

library FixedMath {
    error Overflow();

    /// @notice     Applies mulDivUp to uint96 values, and checks that the result is within the uint96 range
    /// @dev        This function returns the maximum value of uint96 if the product is greater than the maximum value of a uint96
    function mulDivUpNoOverflow(
        uint96 mul1_,
        uint96 mul2_,
        uint96 div_
    ) public pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivUp(mul1_, mul2_, div_);
        if (product > type(uint96).max) return type(uint96).max;

        return uint96(product);
    }

    /// @notice     Applies mulDivUp to uint96 values, and checks that the result is within the uint96 range
    /// @dev        This function reverts if the product is greater than the maximum value of a uint96
    function mulDivUp(uint96 mul1_, uint96 mul2_, uint96 div_) public pure returns (uint96) {
        uint96 product = mulDivUpNoOverflow(mul1_, mul2_, div_);
        if (product == type(uint96).max) revert Overflow();

        return product;
    }
}