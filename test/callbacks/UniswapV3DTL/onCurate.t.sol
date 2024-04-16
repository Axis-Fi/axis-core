// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";

contract UniswapV3DirectToLiquidityOnCurateTest is UniswapV3DirectToLiquidityTest {
    uint96 internal constant _PAYOUT_AMOUNT = 1e18;

    // ============ Modifiers ============ //

    function _performCallback() internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, _PAYOUT_AMOUNT, false, abi.encode(""));
    }

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] it registers the curator payout

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
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.lotCuratorPayout, _PAYOUT_AMOUNT, "lotCuratorPayout");

        // Check the balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)), 0, "auction house base token balance"
        );
    }
}
