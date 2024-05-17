// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

enum Range {
    FLOOR,
    ANCHOR,
    DISCOVERY
}

enum Action {
    ADD,
    REMOVE
}

struct PositionData {
    uint256 bAssets;
    uint256 reserves;
    uint128 liquidity;
    uint160 sqrtPriceL;
    uint160 sqrtPriceU;
}

import {IUniswapV3Pool} from "lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @title  Baseline's UniswapV3 Liquidity Pool Management Module
interface IBPOOLv1 {
    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    // ========= STATE VIEW FUNCTIONS ========== //

    function UPPER_LP_TICK_SPACINGS() external view returns (int24);
    function TICK_SPACING() external view returns (int24);

    function reserve() external view returns (address);
    function pool() external view returns (IUniswapV3Pool);

    function floorTick() external view returns (int24);
    function checkpointTick() external view returns (int24);

    // ========= PERMISSIONED WRITE FUNCTIONS ========= //

    // Setup the pool (can only be called once, subsequent calls will revert on factory.createPool and pool.initialze)
    function initializePool(int24 _initialFloorTick, int24 _initialActiveTick) external;

    function manageReservesFor(
        Range _range,
        Action _action,
        uint256 _reserves
    ) external returns (uint256 bAssetDelta_, uint256 reserveDelta_);

    function manageLiquidityFor(
        Range _range,
        Action _action,
        uint128 _liquidity
    ) external returns (uint256 bAssetsDelta_, uint256 reservesDelta_);

    // Mints a set fee to the brs based on the circulating supply.
    function mint(address _to, uint256 _amount) external;

    // Burns excess bAssets not used in the pool POL.
    // No need to discount collateralizedBAssets because it's in a separate contract now.
    function burnAllBAssetsInContract() external;

    // ========= PUBLIC READ FUNCTIONS ========= //

    // Returns the lower and upper tick values as well as the liquidity amount for a given range
    function getPositionData(Range _range)
        external
        view
        returns (PositionData memory positionData_);

    function getPositionLiquidity(Range _range) external view returns (uint128 liquidity_);

    /// @dev    BPOOL inherits from solmate ERC20
    function decimals() external view returns (uint8);
}
