// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {Range} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract BaselineOnSettleTest is BaselineAxisLaunchTest {
    using FixedPointMathLib for uint256;

    // ============ Modifiers ============ //

    // ============ Assertions ============ //

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] when the caller is not the auction house
    //  [X] it reverts
    // [X] when the lot has already been settled
    //  [X] it reverts
    // [X] when the lot has already been cancelled
    //  [X] it reverts
    // [X] when insufficient proceeds are sent to the callback
    //  [X] it reverts
    // [X] when insufficient refund is sent to the callback
    //  [X] it reverts
    // [X] when the percent in floor reserves changes
    //  [X] it adds reserves to the floor and anchor ranges in the correct proportions
    // [X] it burns refunded base tokens, updates the circulating supply, marks the auction as completed and deploys the reserves into the Baseline pool

    function test_lotNotRegistered_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenAddressHasBaseTokenBalance(_dtlAddress, _REFUND_AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        _onSettle();
    }

    function test_notAuctionHouse_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenAddressHasBaseTokenBalance(_dtlAddress, _LOT_CAPACITY)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Perform callback
        _dtl.onSettle(
            _lotId, _PROCEEDS_AMOUNT, _scaleBaseTokenAmount(_REFUND_AMOUNT), abi.encode("")
        );
    }

    function test_lotAlreadySettled_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenAddressHasBaseTokenBalance(_dtlAddress, _REFUND_AMOUNT)
        givenOnSettle
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Perform callback
        _onSettle();
    }

    function test_lotAlreadyCancelled_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasBaseTokenBalance(_dtlAddress, _LOT_CAPACITY)
        givenOnCancel
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Perform callback
        _onSettle();
    }

    function test_insufficientProceeds_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasBaseTokenBalance(_dtlAddress, _LOT_CAPACITY)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaselineAxisLaunch.Callback_MissingFunds.selector);
        vm.expectRevert(err);

        // Perform callback
        _onSettle();
    }

    function test_insufficientRefund_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaselineAxisLaunch.Callback_MissingFunds.selector);
        vm.expectRevert(err);

        // Perform callback
        _onSettle();
    }

    function test_success()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenAddressHasBaseTokenBalance(_dtlAddress, _REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), _PROCEEDS_AMOUNT, "quote token: pool"
        );

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), 0, "base token: pool"); // No liquidity in the anchor range, so no base token in the discovery range

        // Circulating supply
        assertEq(
            _dtl.initialCirculatingSupply(), _LOT_CAPACITY - _REFUND_AMOUNT, "circulating supply"
        );

        // Auction marked as complete
        assertEq(_dtl.auctionComplete(), true, "auction completed");

        // Reserves deployed into the pool
        assertEq(
            _baseToken.rangeReserves(Range.FLOOR),
            _PROCEEDS_AMOUNT.mulDivDown(_FLOOR_RESERVES_PERCENT, _ONE_HUNDRED_PERCENT),
            "reserves: floor"
        );
        assertEq(
            _baseToken.rangeReserves(Range.ANCHOR),
            _PROCEEDS_AMOUNT.mulDivDown(_ONE_HUNDRED_PERCENT - _FLOOR_RESERVES_PERCENT, _ONE_HUNDRED_PERCENT),
            "reserves: anchor"
        );
        assertEq(_baseToken.rangeReserves(Range.DISCOVERY), 0, "reserves: discovery");

        // Liquidity
        assertEq(_baseToken.rangeLiquidity(Range.FLOOR), 0, "liquidity: floor");
        assertEq(_baseToken.rangeLiquidity(Range.ANCHOR), 0, "liquidity: anchor");
        assertGt(_baseToken.rangeLiquidity(Range.DISCOVERY), 0, "liquidity: discovery");
    }

    function test_floorReservesPercent_fuzz(uint24 floorReservesPercent_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 floorReservesPercent = uint24(bound(floorReservesPercent_, 0, _ONE_HUNDRED_PERCENT));

        // Update the callback parameters
        _createData.floorReservesPercent = floorReservesPercent;

        // Call onCreate
        _onCreate();

        // Mint tokens
        _quoteToken.mint(_dtlAddress, _PROCEEDS_AMOUNT);
        _baseToken.mint(_dtlAddress, _REFUND_AMOUNT);

        // Perform callback
        _onSettle();

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), _PROCEEDS_AMOUNT, "quote token: pool"
        );

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), 0, "base token: pool"); // No liquidity in the anchor range, so no base token in the discovery range

        // Circulating supply
        assertEq(
            _dtl.initialCirculatingSupply(), _LOT_CAPACITY - _REFUND_AMOUNT, "circulating supply"
        );

        // Auction marked as complete
        assertEq(_dtl.auctionComplete(), true, "auction completed");

        // Reserves deployed into the pool
        assertEq(
            _baseToken.rangeReserves(Range.FLOOR),
            _PROCEEDS_AMOUNT.mulDivDown(floorReservesPercent, _ONE_HUNDRED_PERCENT),
            "reserves: floor"
        );
        assertEq(
            _baseToken.rangeReserves(Range.ANCHOR),
            _PROCEEDS_AMOUNT.mulDivDown(_ONE_HUNDRED_PERCENT - floorReservesPercent, _ONE_HUNDRED_PERCENT),
            "reserves: anchor"
        );
        assertEq(_baseToken.rangeReserves(Range.DISCOVERY), 0, "reserves: discovery");

        // Liquidity
        assertEq(_baseToken.rangeLiquidity(Range.FLOOR), 0, "liquidity: floor");
        assertEq(_baseToken.rangeLiquidity(Range.ANCHOR), 0, "liquidity: anchor");
        assertGt(_baseToken.rangeLiquidity(Range.DISCOVERY), 0, "liquidity: discovery");
    }
}
