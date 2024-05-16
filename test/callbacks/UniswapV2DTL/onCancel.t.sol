// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV2DirectToLiquidityTest} from "./UniswapV2DTLTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";

contract UniswapV2DirectToLiquidityOnCancelTest is UniswapV2DirectToLiquidityTest {
    uint96 internal constant _REFUND_AMOUNT = 2e18;

    // ============ Modifiers ============ //

    function _performCallback(uint96 lotId_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCancel(lotId_, _REFUND_AMOUNT, false, abi.encode(""));
    }

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] when multiple lots are created
    //  [X] it marks the correct lot as inactive
    // [X] it marks the lot as inactive

    function test_whenLotNotRegistered_reverts() public givenCallbackIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the function
        _performCallback(_lotId);
    }

    function test_success() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback(_lotId);

        // Check the values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.active, false, "active");

        // Check the balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(_baseToken.balanceOf(_NOT_SELLER), 0, "not seller base token balance");
    }

    function test_success_multiple() public givenCallbackIsCreated givenOnCreate {
        uint96 lotIdOne = _lotId;

        // Create a second lot and cancel it
        uint96 lotIdTwo = _createLot(_NOT_SELLER);
        _performCallback(lotIdTwo);

        // Check the values
        BaseDirectToLiquidity.DTLConfiguration memory configurationOne =
            _getDTLConfiguration(lotIdOne);
        assertEq(configurationOne.active, true, "lot one: active");

        BaseDirectToLiquidity.DTLConfiguration memory configurationTwo =
            _getDTLConfiguration(lotIdTwo);
        assertEq(configurationTwo.active, false, "lot two: active");

        // Check the balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(_baseToken.balanceOf(_NOT_SELLER), 0, "not seller base token balance");
    }
}
