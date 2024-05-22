// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";
import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";
import {TickMath} from "lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

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
            _baseToken.balanceOf(address(_auctionHouse)), _LOT_CAPACITY, "auction house balance"
        );
    }

    // ============ Helper Functions ============ //

    function _getFixedPriceTick() internal view returns (int24) {
        uint160 fixedPriceSqrtPriceX96 =
            SqrtPriceMath.getSqrtPriceX96(address(_quoteToken), address(_baseToken), 30e18, 10e18); // Maintains the ratio of _FIXED_PRICE
        return TickMath.getTickAtSqrtRatio(fixedPriceSqrtPriceX96);
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
    // [ ] when the tick spacing is narrow
    //  [ ] the ticks do not overlap
    // [ ] when the auction fixed price is very high
    //  [ ] it correctly sets the active tick
    // [ ] when the discoveryTickWidth is less than the tick spacing
    //  [ ] it correctly sets the discovery ticks to not overlap with the other ranges
    // [X] it transfers the base token to the auction house, updates circulating supply, sets the state variables, initializes the pool and sets the tick ranges

    function test_callbackDataIncorrect() public givenCallbackIsCreated {
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
            true,
            abi.encode(uint256(10), uint256(20))
        );
    }

    function test_notAuctionHouse() public givenCallbackIsCreated {
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

    function test_lotAlreadyRegistered() public givenCallbackIsCreated {
        // Perform callback
        _onCreate();

        // Expect revert
        _expectInvalidParams();

        // Perform the callback again
        _onCreate();
    }

    function test_baseTokenNotBPool() public givenCallbackIsCreated {
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

    function test_quoteTokenNotReserve() public givenCallbackIsCreated {
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
    {
        // Expect revert
        _expectInvalidParams();

        // Perform the call
        _onCreate();
    }

    function test_auctionNotPrefunded() public givenCallbackIsCreated {
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

    function test_success() public givenCallbackIsCreated {
        console2.log("bAsset", address(_dtl.bAsset()));
        console2.log("reserve", address(_dtl.RESERVE()));
        console2.log("baseToken", address(_baseToken));
        console2.log("quoteToken", address(_quoteToken));

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
}
