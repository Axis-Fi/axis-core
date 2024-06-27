// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {IUniswapV3Pool} from "lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

enum Range {
    FLOOR,
    ANCHOR,
    DISCOVERY
}

struct Ticks {
    int24 lower;
    int24 upper;
}

struct Position {
    uint128 liquidity;
    uint160 sqrtPriceL;
    uint160 sqrtPriceU;
    uint256 bAssets;
    uint256 reserves;
    uint256 capacity;
}

/// @title  Baseline's UniswapV3 Liquidity Pool Management Module
/// @dev    Imported at commit 88bb34b23b1627207e4c8d3fcd9efad22332eb5f
interface IBPOOLv1 {
    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    // ========= STATE VIEW FUNCTIONS ========== //

    function TICK_SPACING() external view returns (int24);

    function reserve() external view returns (ERC20);
    function pool() external view returns (IUniswapV3Pool);

    function getTicks(Range range_) external view returns (int24 tickLower, int24 tickUpper);

    function getLiquidity(Range range_) external view returns (uint128);

    // ========= PERMISSIONED WRITE FUNCTIONS ========= //

    function addReservesTo(
        Range _range,
        uint256 _reserves
    ) external returns (uint256 bAssetsAdded_, uint256 reservesAdded_, uint128 liquidityFinal_);

    function addLiquidityTo(
        Range _range,
        uint128 _liquidity
    ) external returns (uint256 bAssetsAdded_, uint256 reservesAdded_, uint128 liquidityFinal_);

    function removeAllFrom(Range _range)
        external
        returns (
            uint256 bAssetsRemoved_,
            uint256 bAssetFees_,
            uint256 reservesRemoved_,
            uint256 reserveFees_
        );

    function setTicks(Range _range, int24 _lower, int24 _upper) external;

    /// @notice Mints a set fee to the brs based on the circulating supply.
    function mint(address _to, uint256 _amount) external;

    /// @notice Burns excess bAssets not used in the pool POL.
    /// @dev    No need to discount collateralizedBAssets because it's in a separate contract now.
    function burnAllBAssetsInContract() external;

    // ========= PUBLIC READ FUNCTIONS ========= //

    /// @notice Returns the price at the lower tick of the floor position
    function getBaselineValue() external view returns (uint256);

    /// @notice Returns the closest tick spacing boundary above the active tick
    ///         Formerly "upperAnchorTick"
    function getActiveTS() external view returns (int24 activeTS_);

    /// @notice  Wrapper for liquidity data struct
    function getPosition(Range _range) external view returns (Position memory position_);

    function getBalancesForLiquidity(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint128 _liquidity
    ) external view returns (uint256 bAssets_, uint256 reserves_);

    function getLiquidityForReserves(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint256 _reserves,
        uint160 _sqrtPriceA
    ) external view returns (uint128 liquidity_);

    function getCapacityForLiquidity(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint128 _liquidity,
        uint160 _sqrtPriceA
    ) external view returns (uint256 capacity_);

    function getCapacityForReserves(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint256 _reserves
    ) external view returns (uint256 capacity_);
}
