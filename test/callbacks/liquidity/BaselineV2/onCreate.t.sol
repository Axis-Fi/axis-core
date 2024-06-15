// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Range} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";

import {console2} from "forge-std/console2.sol";

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

    /// @notice Returns the tick equivalent to the fixed price of the auction
    /// @dev    This function contains pre-calculated tick values, to prevent the implementation and tests using the same library.
    ///
    ///         This function also handles a set number of decimal permutations.
    function _getFixedPriceTick() internal view returns (int24) {
        // Calculation source: https://blog.uniswap.org/uniswap-v3-math-primer#how-does-tick-and-tick-spacing-relate-to-sqrtpricex96

        // Quote token is token1
        if (address(_quoteToken) > address(_baseToken)) {
            if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 18) {
                // Fixed price = 3e18
                // SqrtPriceX96 = sqrt(3e18 * 2^192 / 1e18)
                //              = 1.3722720287e29
                // Tick = log((1.3722720287e29 / 2^96)^2) / log(1.0001)
                //      = 10,986.672184372 (rounded down)
                // Price = 1.0001^10986 / (10^(18-18)) = 2.9997983618
                return 10_986;
            }

            if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 17) {
                // Fixed price = 3e18
                // SqrtPriceX96 = sqrt(3e18 * 2^192 / 1e17)
                //              = 4.3395051823e29
                // Tick = log((4.3395051823e29 / 2^96)^2) / log(1.0001)
                //      = 34,013.6743980767 (rounded down)
                // Price = 1.0001^34013 / (10^(18-17)) = 2.9997977008
                return 34_013;
            }

            if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 19) {
                // Fixed price = 3e18
                // SqrtPriceX96 = sqrt(3e18 * 2^192 / 1e19)
                //              = 4.3395051799e28
                // Tick = log((4.3395051799e28 / 2^96)^2) / log(1.0001)
                //      = -12,040.3300194873 (rounded down)
                // Price = 1.0001^-12041 / (10^(18-19)) = 2.9997990227
                return -12_041;
            }

            revert("Unsupported decimal permutation");
        }

        // Quote token is token0
        if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 18) {
            // Fixed price = 3e18
            // SqrtPriceX96 = sqrt(1e18 * 2^192 / 3e18)
            //              = 4.574240096e28
            // Tick = log((4.574240096e28 / 2^96)^2) / log(1.0001)
            //      = -10,986.6721814657 (rounded down)
            // Price = 1.0001^-10987 / (10^(18-18)) = 0.3333224068 = 0.3 base token per 1 quote token
            return -10_987;
        }

        if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 17) {
            // Fixed price = 3e18
            // SqrtPriceX96 = sqrt(1e17 * 2^192 / 3e18)
            //              = 1.4465017266e28
            // Tick = log((1.4465017266e28 / 2^96)^2) / log(1.0001)
            //      = -34,013.6743872434 (rounded down)
            // Price = 1.0001^-34014 / (10^(17-18)) = 0.3333224803 = 0.3 base token per 1 quote token
            return -34_014;
        }

        if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 19) {
            // Fixed price = 3e18
            // SqrtPriceX96 = sqrt(1e19 * 2^192 / 3e18)
            //              = 1.4465017267e29
            // Tick = log((1.4465017267e29 / 2^96)^2) / log(1.0001)
            //      = 12,040.3300206416 (rounded down)
            // Price = 1.0001^12040 / (10^(19-18)) = 0.3333223334 = 0.3 base token per 1 quote token
            return 12_040;
        }

        revert("Unsupported decimal permutation");
    }

    function _roundToTickSpacingUp(int24 tick_) internal view returns (int24) {
        // Rounds down
        int24 roundedTick = (tick_ / _tickSpacing) * _tickSpacing;

        // Add a tick spacing to round up
        if (tick_ > roundedTick) {
            roundedTick += _tickSpacing;
        }

        return roundedTick;
    }

    function _assertTicks(int24 fixedPriceTick_) internal {
        assertEq(_baseToken.activeTick(), fixedPriceTick_, "active tick");
        console2.log("Active tick: ", _baseToken.activeTick());

        // Calculate the active tick with rounding
        int24 anchorTickUpper = _roundToTickSpacingUp(fixedPriceTick_);
        int24 anchorTickLower = anchorTickUpper - _createData.anchorTickWidth * _tickSpacing;
        console2.log("Anchor tick lower: ", anchorTickLower);
        console2.log("Anchor tick upper: ", anchorTickUpper);

        // Active tick should be within the anchor range
        assertGt(fixedPriceTick_, anchorTickLower, "active tick > anchor tick lower");
        assertLe(fixedPriceTick_, anchorTickUpper, "active tick <= anchor tick upper");

        // Anchor range should be the width of anchorTickWidth * tick spacing
        (int24 anchorTickLower_, int24 anchorTickUpper_) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower_, anchorTickLower, "anchor tick lower");
        assertEq(anchorTickUpper_, anchorTickUpper, "anchor tick upper");

        // Floor range should be the width of the tick spacing and below the anchor range
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, anchorTickLower_ - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, anchorTickLower_, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, anchorTickUpper_, "discovery tick lower");
        assertEq(
            discoveryTickUpper,
            anchorTickUpper_ + _createData.discoveryTickWidth * _tickSpacing,
            "discovery tick upper"
        );
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
    // [X] when the floorReservesPercent is not between 0 and 100%
    //  [X] it reverts
    // [X] when the anchorTickWidth is <= 0
    //  [X] it reverts
    // [X] when the discoveryTickWidth is <= 0
    //  [X] it reverts
    // [X] when the auction format is not FPB
    //  [X] it reverts
    // [X] when the auction is not prefunded
    //  [X] it reverts
    // [X] when the floorReservesPercent is 0-100%
    //  [X] it correctly records the allocation
    // [X] when the tick spacing is narrow
    //  [X] the ticks do not overlap
    // [X] when the auction fixed price is very high
    //  [X] it correctly sets the active tick
    // [X] when the auction fixed price is very low
    //  [X] it correctly sets the active tick
    // [X] when the base token address is lower than the quote token address
    //  [X] it correctly sets the active tick
    // [X] when the quote token decimals are higher than the base token decimals
    //  [X] it correctly sets the active tick
    // [X] when the quote token decimals are lower than the base token decimals
    //  [X] it correctly sets the active tick
    // [X] when the anchorTickWidth is small
    //  [X] it correctly sets the anchor ticks to not overlap with the other ranges
    // [X] when the discoveryTickWidth is small
    //  [X] it correctly sets the discovery ticks to not overlap with the other ranges
    // [X] it transfers the base token to the auction house, updates circulating supply, sets the state variables, initializes the pool and sets the tick ranges

    function test_callbackDataIncorrect_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
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

    function test_notAuctionHouse_reverts() public givenCallbackIsCreated givenAuctionIsCreated {
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

    function test_lotAlreadyRegistered_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform callback
        _onCreate();

        // Expect revert
        _expectInvalidParams();

        // Perform the callback again
        _onCreate();
    }

    function test_baseTokenNotBPool_reverts() public givenCallbackIsCreated givenAuctionIsCreated {
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

    function test_quoteTokenNotReserve_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
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

    function test_floorReservesPercentInvalid_reverts(uint24 floorReservesPercent_)
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 floorReservesPercent =
            uint24(bound(floorReservesPercent_, 1e5 + 1, type(uint24).max));
        _createData.floorReservesPercent = floorReservesPercent;

        // Expect revert
        _expectInvalidParams();

        // Perform the call
        _onCreate();
    }

    function test_anchorTickWidthInvalid_reverts(int24 anchorTickWidth_)
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        int24 anchorTickWidth = int24(bound(anchorTickWidth_, type(int24).min, 0));
        _createData.anchorTickWidth = anchorTickWidth;

        // Expect revert
        _expectInvalidParams();

        // Perform the call
        _onCreate();
    }

    function test_discoveryTickWidthInvalid_reverts(int24 discoveryTickWidth_)
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        int24 discoveryTickWidth = int24(bound(discoveryTickWidth_, type(int24).min, 0));
        _createData.discoveryTickWidth = discoveryTickWidth;

        // Expect revert
        _expectInvalidParams();

        // Perform the call
        _onCreate();
    }

    function test_givenAuctionFormatNotFixedPriceBatch_reverts()
        public
        givenCallbackIsCreated
        givenAuctionFormatIsEmp
        givenAuctionIsCreated
    {
        // Expect revert
        _expectInvalidParams();

        // Perform the call
        _onCreate();
    }

    function test_auctionNotPrefunded_reverts()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
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

    function test_success() public givenCallbackIsCreated givenAuctionIsCreated {
        // Perform the call
        _onCreate();

        // Check that the callback owner is correct
        assertEq(_dtl.owner(), _OWNER, "owner");

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_dtl.initialCirculatingSupply(), _LOT_CAPACITY, "circulating supply");

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);
    }

    function test_floorReservesPercent(uint24 floorReservesPercent_)
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 floorReservesPercent = uint24(bound(floorReservesPercent_, 0, 1e5));
        _createData.floorReservesPercent = floorReservesPercent;

        // Perform the call
        _onCreate();

        // Assert
        assertEq(_dtl.floorReservesPercent(), floorReservesPercent, "floor reserves percent");
    }

    function test_tickSpacingNarrow()
        public
        givenBPoolFeeTier(500)
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);
    }

    function test_auctionHighPrice()
        public
        givenCallbackIsCreated
        givenFixedPrice(3e56)
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_dtl.initialCirculatingSupply(), _LOT_CAPACITY, "circulating supply");

        // Calculation for the maximum price
        // By default, quote token is token0
        // Minimum sqrtPriceX96 = MIN_SQRT_RATIO = 4_295_128_739
        // 4_295_128_739^2 = 1e18 * 2^192 / amount0
        // amount0 = 1e18 * 2^192 / 4_295_128_739^2 = 3.402567867e56 ~= 3e56

        // SqrtPriceX96 = sqrt(1e18 * 2^192 / 3e56)
        //              = 4,574,240,095.5009932534
        // Tick = log((4,574,240,095.5009932534 / 2^96)^2) / log(1.0001)
        //      = -886,012.7559071901 (rounded down)
        // Price = 1.0001^-886013 / (10^(18-18)) = 0
        int24 fixedPriceTick = -886_013;

        _assertTicks(fixedPriceTick);
    }

    function test_auctionLowPrice()
        public
        givenCallbackIsCreated
        givenFixedPrice(1)
        givenAuctionIsCreated
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
        // By default, quote token is token0
        // Fixed price = 1
        // SqrtPriceX96 = sqrt(1e18 * 2^192 / 1)
        //              = 7.9228162514e37
        // Tick = log((7.9228162514e37 / 2^96)^2) / log(1.0001)
        //      = 414,486.0396584532 (rounded down)
        // Price = 1.0001^414486 / (10^(18-18)) = 9.9999603427e17
        int24 fixedPriceTick = 414_486;

        _assertTicks(fixedPriceTick);
    }

    function test_narrowAnchorTickWidth()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(1)
    {
        // Perform the call
        _onCreate();

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);
    }

    function test_narrowDiscoveryTickWidth()
        public
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenDiscoveryTickWidth(1)
    {
        // Perform the call
        _onCreate();

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);
    }

    function test_baseTokenAddressLower()
        public
        givenBaseTokenAddressLower
        givenCallbackIsCreated
        givenAuctionIsCreated
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

        _assertTicks(fixedPriceTick);
    }

    function test_baseTokenDecimalsHigher()
        public
        givenBaseTokenDecimals(19)
        givenCallbackIsCreated
        givenAuctionIsCreated
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

        _assertTicks(fixedPriceTick);
    }

    function test_baseTokenDecimalsLower()
        public
        givenBaseTokenDecimals(17)
        givenCallbackIsCreated
        givenAuctionIsCreated
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

        _assertTicks(fixedPriceTick);
    }

    function test_activeTickRounded()
        public
        givenBPoolFeeTier(10_000)
        givenCallbackIsCreated
        givenFixedPrice(1e18)
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // Check that the callback owner is correct
        assertEq(_dtl.owner(), _OWNER, "owner");

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_dtl.initialCirculatingSupply(), _LOT_CAPACITY, "circulating supply");

        int24 fixedPriceTick = 0;

        _assertTicks(fixedPriceTick);
    }
}
