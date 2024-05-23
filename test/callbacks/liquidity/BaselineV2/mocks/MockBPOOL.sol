// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IBPOOLv1, Range, Position, Ticks} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IUniswapV3Pool} from "lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract MockBPOOL is IBPOOLv1, ERC20 {
    int24 public immutable TICK_SPACING;
    uint24 public immutable FEE_TIER;

    ERC20 public immutable reserve;

    IUniswapV3Pool public pool;
    IUniswapV3Factory public immutable factory;

    mapping(Range => Ticks) public getTicks;

    mapping(Range => uint256) public _rangeReserves;

    int24 public activeTick;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address factory_,
        address reserve_,
        uint24 feeTier_
    ) ERC20(name_, symbol_, decimals_) {
        factory = IUniswapV3Factory(factory_);
        reserve = ERC20(reserve_);
        FEE_TIER = feeTier_;
        TICK_SPACING = factory.feeAmountTickSpacing(feeTier_);
    }

    function getLiquidity(Range range_) external view override returns (uint128) {}

    function initializePool(int24 activeTick_) external override returns (IUniswapV3Pool) {
        activeTick = activeTick_;

        return pool;
    }

    function addReservesTo(
        Range _range,
        uint256 _reserves
    )
        external
        override
        returns (uint256 bAssetsAdded_, uint256 reservesAdded_, uint128 liquidityFinal_)
    {
        reserve.transferFrom(msg.sender, address(this), _reserves);

        _rangeReserves[_range] += _reserves;

        return (0, _reserves, 0);
    }

    function addLiquidityTo(
        Range _range,
        uint128 _liquidity
    )
        external
        override
        returns (uint256 bAssetsAdded_, uint256 reservesAdded_, uint128 liquidityFinal_)
    {}

    function removeAllFrom(Range _range)
        external
        override
        returns (
            uint256 bAssetsRemoved_,
            uint256 bAssetFees_,
            uint256 reservesRemoved_,
            uint256 reserveFees_
        )
    {}

    function setTicks(Range _range, int24 _lower, int24 _upper) external override {
        if (_lower > _upper) revert("Invalid tick range");

        getTicks[_range] = Ticks({lower: _lower, upper: _upper});
    }

    function mint(address _to, uint256 _amount) external override {
        _mint(_to, _amount);
    }

    function burnAllBAssetsInContract() external override {
        _burn(address(this), balanceOf[address(this)]);
    }

    function getBaselineValue() external view override returns (uint256) {}

    function getActiveTS() external view override returns (int24 activeTS_) {
        return (activeTick / TICK_SPACING) * TICK_SPACING;
    }

    function getPosition(Range range_) external view override returns (Position memory position) {
        return Position({
            liquidity: 0,
            sqrtPriceL: 0,
            sqrtPriceU: 0,
            bAssets: 0,
            reserves: _rangeReserves[range_],
            capacity: _rangeReserves[range_]
        });
    }

    function getBalancesForLiquidity(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint128 _liquidity
    ) external view override returns (uint256 bAssets_, uint256 reserves_) {}

    function getLiquidityForReserves(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint256 _reserves
    ) external view override returns (uint128 liquidity_) {}

    function getCapacityForLiquidity(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint128 _liquidity
    ) external view override returns (uint256 capacity_) {}

    function getCapacityForReserves(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint256 _reserves
    ) external view override returns (uint256 capacity_) {}
}
