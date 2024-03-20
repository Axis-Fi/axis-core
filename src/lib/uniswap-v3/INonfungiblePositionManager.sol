// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

/// @dev       Simplified interface for INonfungiblePositionManager, which avoids issues with dependencies in uniswap-v3-periphery
interface INonfungiblePositionManager {
    function factory() external view returns (address);

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
}
