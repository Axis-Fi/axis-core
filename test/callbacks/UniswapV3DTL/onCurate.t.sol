// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";

contract UniswapV3DirectToLiquidityOnCurateTest is UniswapV3DirectToLiquidityTest {
    uint96 internal constant _PAYOUT_AMOUNT = 1e18;

    // ============ Modifiers ============ //

    function _performCallback() internal {
        bool isPrefund = _callbackPermissions.sendBaseTokens;

        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, _PAYOUT_AMOUNT, isPrefund, abi.encode(""));
    }

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] given the send base tokens flag is enabled
    //  [X] given the seller has an insufficient balance
    //   [X] it reverts
    //  [X] given the seller has an insufficient allowance
    //   [X] it reverts
    //  [X] it transfers the base tokens to the auction house
    // [X] it does nothing

    function test_whenLotNotRegistered_reverts() public givenCallbackIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the function
        _performCallback();
    }

    function test_givenSendBaseTokens_givenInsufficientBalance_reverts()
        public
        givenCallbackSendBaseTokensIsSet
        givenCallbackIsCreated
        givenAddressHasBaseTokenAllowance(_SELLER, address(_dtl), _PAYOUT_AMOUNT)
        givenOnCreate
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call the function
        _performCallback();
    }

    function test_givenSendBaseTokens_givenInsufficientAllowance_reverts()
        public
        givenCallbackSendBaseTokensIsSet
        givenCallbackIsCreated
        givenAddressHasBaseTokenBalance(_SELLER, _PAYOUT_AMOUNT)
        givenOnCreate
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call the function
        _performCallback();
    }

    function test_givenSendBaseTokens()
        public
        givenCallbackSendBaseTokensIsSet
        givenCallbackIsCreated
        givenAddressHasBaseTokenBalance(_SELLER, _PAYOUT_AMOUNT)
        givenAddressHasBaseTokenAllowance(_SELLER, address(_dtl), _PAYOUT_AMOUNT)
        givenOnCreate
    {
        // Call the function
        _performCallback();

        // Check the values
        UniswapV3DirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(configuration.lotCuratorPayout, _PAYOUT_AMOUNT, "lotCuratorPayout");

        // Check the balances
        assertEq(_baseToken.balanceOf(address(_dtl)), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _PAYOUT_AMOUNT,
            "auction house base token balance"
        );
    }

    function test_success() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback();

        // Check the values
        UniswapV3DirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(configuration.lotCuratorPayout, _PAYOUT_AMOUNT, "lotCuratorPayout");

        // Check the balances
        assertEq(_baseToken.balanceOf(address(_dtl)), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)), 0, "auction house base token balance"
        );
    }
}
