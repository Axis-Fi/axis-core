/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

library FixedMath {
    error Overflow();

    /// @notice     Applies mulDivDown to uint96 values, and checks that the result is within the uint96 range
    /// @dev        This function reverts if the product is greater than the maximum value of a uint96
    function mulDivDown96(
        uint256 mul1_,
        uint256 mul2_,
        uint256 div_
    ) public pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivDown(mul1_, mul2_, div_);
        if (product == type(uint96).max) revert Overflow();

        return uint96(product);
    }

    /// @notice     Applies mulDivUp to uint96 values, and checks that the result is within the uint96 range
    /// @dev        This function reverts if the product is greater than the maximum value of a uint96
    function mulDivUp96(uint256 mul1_, uint256 mul2_, uint256 div_) public pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivUp(mul1_, mul2_, div_);
        if (product == type(uint96).max) revert Overflow();

        return uint96(product);
    }
}
