// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BaseUniswapDirectToLiquidity} from "src/callbacks/liquidity/BaseUniswapDTL.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";

contract UniswapV3DirectToLiquidityOnCancelTest is UniswapV3DirectToLiquidityTest {
    uint96 internal constant _REFUND_AMOUNT = 2e18;

    // ============ Modifiers ============ //

    function _performCallback() internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCancel(_lotId, _REFUND_AMOUNT, false, abi.encode(""));
    }

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] it marks the lot as inactive

    function test_whenLotNotRegistered_reverts() public givenCallbackIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the function
        _performCallback();
    }

    function test_success() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback();

        // Check the values
        BaseUniswapDirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(configuration.active, false, "active");

        // Check the balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
    }
}
