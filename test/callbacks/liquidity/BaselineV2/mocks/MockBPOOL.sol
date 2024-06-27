// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IBPOOLv1, Range, Position, Ticks} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IUniswapV3Pool} from "lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "lib/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {TickMath} from "lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

contract MockBPOOL is IBPOOLv1, ERC20 {
    int24 public immutable TICK_SPACING;
    uint24 public immutable FEE_TIER;

    ERC20 public immutable reserve;

    IUniswapV3Pool public pool;
    IUniswapV3Factory public immutable factory;

    mapping(Range => Ticks) public getTicks;

    mapping(Range => uint256) public rangeReserves;
    mapping(Range => uint128) public rangeLiquidity;

    int24 public activeTick;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address factory_,
        address reserve_,
        uint24 feeTier_,
        int24 initialActiveTick_
    ) ERC20(name_, symbol_, decimals_) {
        factory = IUniswapV3Factory(factory_);
        reserve = ERC20(reserve_);
        FEE_TIER = feeTier_;
        TICK_SPACING = factory.feeAmountTickSpacing(feeTier_);

        // This mimics the behaviour of the real BPOOLv1 module
        // Create the pool
        pool = IUniswapV3Pool(factory.createPool(address(this), address(reserve), FEE_TIER));

        // Set the initial active tick
        pool.initialize(TickMath.getSqrtRatioAtTick(initialActiveTick_));
        activeTick = initialActiveTick_;
    }

    function getLiquidity(Range range_) external view override returns (uint128) {
        // If the reserves are 0, the liquidity is 0
        if (rangeReserves[range_] == 0) {
            return 0;
        }

        // If the reserves are not 0, the liquidity is a non-zero value
        return 1;
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

        rangeReserves[_range] += _reserves;

        // Mimic the Uniswap V3 callback transferring into the pool
        reserve.transfer(address(pool), _reserves);

        return (0, _reserves, 0);
    }

    function addLiquidityTo(
        Range _range,
        uint128 _liquidity
    )
        external
        override
        returns (uint256 bAssetsAdded_, uint256 reservesAdded_, uint128 liquidityFinal_)
    {
        rangeLiquidity[_range] += _liquidity;

        return (0, 0, rangeLiquidity[_range]);
    }

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

    function getActiveTS() public view returns (int24) {
        (, int24 tick,,,,,) = pool.slot0();

        // Round down to the nearest active tick spacing
        tick = ((tick / TICK_SPACING) * TICK_SPACING);

        // Properly handle negative numbers and edge cases
        if (tick >= 0 || tick % TICK_SPACING == 0) {
            tick += TICK_SPACING;
        }

        return tick;
    }

    function getPosition(Range range_) external view override returns (Position memory position) {
        return Position({
            liquidity: 0,
            sqrtPriceL: 0,
            sqrtPriceU: 0,
            bAssets: 0,
            reserves: rangeReserves[range_],
            capacity: rangeReserves[range_]
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
        uint256 _reserves,
        uint160 _sqrtPriceA
    ) external view override returns (uint128 liquidity_) {}

    function getCapacityForLiquidity(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint128 _liquidity,
        uint160 _sqrtPriceA
    ) external view override returns (uint256 capacity_) {}

    function getCapacityForReserves(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint256 _reserves
    ) external view override returns (uint256 capacity_) {}
}
