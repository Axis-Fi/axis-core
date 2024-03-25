// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";

contract UniswapV3DirectToLiquidityOnCancelTest is UniswapV3DirectToLiquidityTest {
    uint96 internal constant _REFUND_AMOUNT = 2e18;

    // ============ Modifiers ============ //

    function _performCallback() internal {
        bool isPrefund = _callbackPermissions.sendBaseTokens;

        vm.prank(address(_auctionHouse));
        _dtl.onCancel(_lotId, _REFUND_AMOUNT, isPrefund, abi.encode(""));
    }

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] given the send base tokens flag is true
    //  [X] it marks the lot as inactive, it transfers the base tokens to the seller
    // [X] it marks the lot as inactive

    function test_whenLotNotRegistered_reverts() public givenCallbackIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the function
        _performCallback();
    }

    function test_givenSendBaseTokens()
        public
        givenCallbackSendBaseTokensIsSet
        givenCallbackIsCreated
        givenOnCreate
        givenAddressHasBaseTokenBalance(address(_dtl), _REFUND_AMOUNT)
    {
        // Call the function
        _performCallback();

        // Check the values
        UniswapV3DirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(configuration.active, false, "active");

        // Check the balances
        assertEq(_baseToken.balanceOf(address(_dtl)), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), _REFUND_AMOUNT, "seller base token balance");
    }

    function test_success() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback();

        // Check the values
        UniswapV3DirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(configuration.active, false, "active");

        // Check the balances
        assertEq(_baseToken.balanceOf(address(_dtl)), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
    }
}
