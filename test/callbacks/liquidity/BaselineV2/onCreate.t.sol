// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";
import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";
import {TickMath} from "lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Range} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";

contract BaselineOnCreateTest is BaselineAxisLaunchTest {
    // ============ Modifiers ============ //

    // ============ Assertions ============ //

    function _expectTransferFrom() internal {
        vm.expectRevert("TRANSFER_FROM_FAILED");
    }

    function _expectInvalidParams() internal {
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);
    }

    function _expectNotAuthorized() internal {
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);
    }

    function _assertBaseTokenBalances() internal {
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller balance");
        assertEq(_baseToken.balanceOf(_NOT_SELLER), 0, "not seller balance");
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "dtl balance");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance"
        );
    }

    // ============ Helper Functions ============ //

    function _getFixedPriceTick() internal view returns (int24) {
        // Calculation source: https://blog.uniswap.org/uniswap-v3-math-primer#how-does-tick-and-tick-spacing-relate-to-sqrtpricex96

        // When the quote token is token1:
        // Price = 3e18
        // SqrtPriceX96 = sqrt(3e18 * 2^192 / 1e18)
        //              = 1.3722720287e29
        // Tick = log((1.3722720287e29 / 2^96)^2) / log(1.0001)
        //      = 10986 (rounded down)
        if (address(_quoteToken) > address(_baseToken)) {
            return 10_986;
        }

        // When the quote token is token0
        // Price = 3e18
        // SqrtPriceX96 = sqrt(1e18 * 2^192 / 3e18)
        //              = 4.574240096e28
        // Tick = log((4.574240096e28 / 2^96)^2) / log(1.0001)
        //      = -10987 (rounded down)
        return -10_987;
    }

    function _roundToTickSpacing(int24 tick) internal view returns (int24) {
        return (tick / _tickSpacing) * _tickSpacing;
    }

    // ============ Tests ============ //

    // [X] when the callback data is incorrect
    //  [X] it reverts
    // [X] when the callback is not called by the auction house
    //  [X] it reverts
    // [X] when the lot has already been registered
    //  [X] it reverts
    // [X] when the base token is not the BPOOL
    //  [X] it reverts
    // [X] when the quote token is not the reserve
    //  [X] it reverts
    // [X] when the discoveryTickWidth is <= 0
    //  [X] it reverts
    // [X] when the auction format is not FPB
    //  [X] it reverts
    // [X] when the auction is not prefunded
    //  [X] it reverts
    // [X] when the tick spacing is narrow
    //  [X] the ticks do not overlap
    // [X] when the auction fixed price is very high
    //  [X] it correctly sets the active tick
    // [ ] when the auction fixed price is very low
    //  [ ] it correctly sets the active tick
    // [X] when the base token address is lower than the quote token address
    //  [X] it correctly sets the active tick
    // [X] when the quote token decimals are higher than the base token decimals
    //  [X] it correctly sets the active tick
    // [X] when the quote token decimals are lower than the base token decimals
    //  [X] it correctly sets the active tick
    // [X] when the discoveryTickWidth is small
    //  [X] it correctly sets the discovery ticks to not overlap with the other ranges
    // [X] it transfers the base token to the auction house, updates circulating supply, sets the state variables, initializes the pool and sets the tick ranges

    function test_callbackDataIncorrect() public givenCallbackIsCreated givenAuctionisCreated {
        // Expect revert
        vm.expectRevert();

        // Perform the call
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            true,
            abi.encode(uint256(10), uint256(20))
        );
    }

    function test_notAuctionHouse() public givenCallbackIsCreated givenAuctionisCreated {
        // Expect revert
        _expectNotAuthorized();

        // Perform the call
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            true,
            abi.encode(_createData)
        );
    }

    function test_lotAlreadyRegistered() public givenCallbackIsCreated givenAuctionisCreated {
        // Perform callback
        _onCreate();

        // Expect revert
        _expectInvalidParams();

        // Perform the callback again
        _onCreate();
    }

    function test_baseTokenNotBPool() public givenCallbackIsCreated givenAuctionisCreated {
        // Expect revert
        _expectInvalidParams();

        // Perform the call
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_quoteToken), // Will revert as the quote token != BPOOL
            address(_quoteToken),
            _LOT_CAPACITY,
            true,
            abi.encode(_createData)
        );
    }

    function test_quoteTokenNotReserve() public givenCallbackIsCreated givenAuctionisCreated {
        // Expect revert
        _expectInvalidParams();

        // Perform the call
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_baseToken), // Will revert as the base token != RESERVE
            _LOT_CAPACITY,
            true,
            abi.encode(_createData)
        );
    }

    function test_invalidDiscoveryTickWidth(int24 discoveryTickWidth_)
        public
        givenCallbackIsCreated
        givenAuctionisCreated
    {
        int24 discoveryTickWidth = int24(bound(discoveryTickWidth_, type(int24).min, 0));
        _createData.discoveryTickWidth = discoveryTickWidth;

        // Expect revert
        _expectInvalidParams();

        // Perform the call
        _onCreate();
    }

    function test_givenAuctionFormatNotFixedPriceBatch()
        public
        givenCallbackIsCreated
        givenAuctionFormatIsEmp
        givenAuctionisCreated
    {
        // Expect revert
        _expectInvalidParams();

        // Perform the call
        _onCreate();
    }

    function test_auctionNotPrefunded() public givenCallbackIsCreated givenAuctionisCreated {
        // Expect revert
        _expectInvalidParams();

        // Perform the call
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false, // Will revert as the auction is not prefunded
            abi.encode(_createData)
        );
    }

    function test_success() public givenCallbackIsCreated givenAuctionisCreated {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_dtl.initialCirculatingSupply(), _LOT_CAPACITY, "circulating supply");

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();
        assertEq(_baseToken.activeTick(), fixedPriceTick, "active tick");

        // Calculate the active tick with rounding
        int24 activeTickWithRounding = _roundToTickSpacing(fixedPriceTick);

        // Anchor range should be 0 width and equal to activeTickWithRounding
        (int24 anchorTickLower, int24 anchorTickUpper) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower, activeTickWithRounding, "anchor tick lower");
        assertEq(anchorTickUpper, activeTickWithRounding, "anchor tick upper");

        // Floor range should be the width of the tick spacing and below the active tick
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, activeTickWithRounding - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, activeTickWithRounding, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, activeTickWithRounding, "discovery tick lower");
        assertEq(
            discoveryTickUpper,
            activeTickWithRounding + _DISCOVERY_TICK_WIDTH * _tickSpacing,
            "discovery tick upper"
        );
    }

    function test_tickSpacingNarrow()
        public
        givenBPoolFeeTier(500)
        givenCallbackIsCreated
        givenAuctionisCreated
    {
        // Perform the call
        _onCreate();

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();
        assertEq(_baseToken.activeTick(), fixedPriceTick, "active tick");

        // Calculate the active tick with rounding
        int24 activeTickWithRounding = _roundToTickSpacing(fixedPriceTick);

        // Anchor range should be 0 width and equal to activeTickWithRounding
        (int24 anchorTickLower, int24 anchorTickUpper) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower, activeTickWithRounding, "anchor tick lower");
        assertEq(anchorTickUpper, activeTickWithRounding, "anchor tick upper");

        // Floor range should be the width of the tick spacing and below the active tick
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, activeTickWithRounding - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, activeTickWithRounding, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, activeTickWithRounding, "discovery tick lower");
        assertEq(
            discoveryTickUpper,
            activeTickWithRounding + _DISCOVERY_TICK_WIDTH * _tickSpacing,
            "discovery tick upper"
        );
    }

    function test_auctionHighPrice()
        public
        givenCallbackIsCreated
        givenFixedPrice(type(uint256).max)
        givenAuctionisCreated
    {
        // Perform the call
        _onCreate();

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();
        assertEq(_baseToken.activeTick(), fixedPriceTick, "active tick");

        // Calculate the active tick with rounding
        int24 activeTickWithRounding = _roundToTickSpacing(fixedPriceTick);

        // Anchor range should be 0 width and equal to activeTickWithRounding
        (int24 anchorTickLower, int24 anchorTickUpper) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower, activeTickWithRounding, "anchor tick lower");
        assertEq(anchorTickUpper, activeTickWithRounding, "anchor tick upper");

        // Floor range should be the width of the tick spacing and below the active tick
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, activeTickWithRounding - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, activeTickWithRounding, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, activeTickWithRounding, "discovery tick lower");
        assertEq(
            discoveryTickUpper,
            activeTickWithRounding + _DISCOVERY_TICK_WIDTH * _tickSpacing,
            "discovery tick upper"
        );
    }

    function test_narrowDiscoveryTickWidth()
        public
        givenCallbackIsCreated
        givenAuctionisCreated
        givenDiscoveryTickWidth(1)
    {
        // Perform the call
        _onCreate();

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();
        assertEq(_baseToken.activeTick(), fixedPriceTick, "active tick");

        // Calculate the active tick with rounding
        int24 activeTickWithRounding = _roundToTickSpacing(fixedPriceTick);

        // Anchor range should be 0 width and equal to activeTickWithRounding
        (int24 anchorTickLower, int24 anchorTickUpper) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower, activeTickWithRounding, "anchor tick lower");
        assertEq(anchorTickUpper, activeTickWithRounding, "anchor tick upper");

        // Floor range should be the width of the tick spacing and below the active tick
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, activeTickWithRounding - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, activeTickWithRounding, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, activeTickWithRounding, "discovery tick lower");
        assertEq(
            discoveryTickUpper, activeTickWithRounding + 1 * _tickSpacing, "discovery tick upper"
        );
    }

    function test_baseTokenAddressLower()
        public
        givenBaseTokenAddressLower
        givenCallbackIsCreated
        givenAuctionisCreated
    {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_dtl.initialCirculatingSupply(), _LOT_CAPACITY, "circulating supply");

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();
        assertEq(_baseToken.activeTick(), fixedPriceTick, "active tick");

        // Calculate the active tick with rounding
        int24 activeTickWithRounding = _roundToTickSpacing(fixedPriceTick);

        // Anchor range should be 0 width and equal to activeTickWithRounding
        (int24 anchorTickLower, int24 anchorTickUpper) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower, activeTickWithRounding, "anchor tick lower");
        assertEq(anchorTickUpper, activeTickWithRounding, "anchor tick upper");

        // Floor range should be the width of the tick spacing and below the active tick
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, activeTickWithRounding - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, activeTickWithRounding, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, activeTickWithRounding, "discovery tick lower");
        assertEq(
            discoveryTickUpper,
            activeTickWithRounding + _DISCOVERY_TICK_WIDTH * _tickSpacing,
            "discovery tick upper"
        );
    }

    function test_baseTokenDecimalsHigher()
        public
        givenBaseTokenDecimals(19)
        givenCallbackIsCreated
        givenAuctionisCreated
    {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(
            _dtl.initialCirculatingSupply(),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "circulating supply"
        );

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();
        assertEq(_baseToken.activeTick(), fixedPriceTick, "active tick");

        // Calculate the active tick with rounding
        int24 activeTickWithRounding = _roundToTickSpacing(fixedPriceTick);

        // Anchor range should be 0 width and equal to activeTickWithRounding
        (int24 anchorTickLower, int24 anchorTickUpper) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower, activeTickWithRounding, "anchor tick lower");
        assertEq(anchorTickUpper, activeTickWithRounding, "anchor tick upper");

        // Floor range should be the width of the tick spacing and below the active tick
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, activeTickWithRounding - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, activeTickWithRounding, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, activeTickWithRounding, "discovery tick lower");
        assertEq(
            discoveryTickUpper,
            activeTickWithRounding + _DISCOVERY_TICK_WIDTH * _tickSpacing,
            "discovery tick upper"
        );
    }

    function test_baseTokenDecimalsLower()
        public
        givenBaseTokenDecimals(17)
        givenCallbackIsCreated
        givenAuctionisCreated
    {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(
            _dtl.initialCirculatingSupply(),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "circulating supply"
        );

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();
        assertEq(_baseToken.activeTick(), fixedPriceTick, "active tick");

        // Calculate the active tick with rounding
        int24 activeTickWithRounding = _roundToTickSpacing(fixedPriceTick);

        // Anchor range should be 0 width and equal to activeTickWithRounding
        (int24 anchorTickLower, int24 anchorTickUpper) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower, activeTickWithRounding, "anchor tick lower");
        assertEq(anchorTickUpper, activeTickWithRounding, "anchor tick upper");

        // Floor range should be the width of the tick spacing and below the active tick
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, activeTickWithRounding - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, activeTickWithRounding, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, activeTickWithRounding, "discovery tick lower");
        assertEq(
            discoveryTickUpper,
            activeTickWithRounding + _DISCOVERY_TICK_WIDTH * _tickSpacing,
            "discovery tick upper"
        );
    }
}
