// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV2DirectToLiquidityTest} from "./UniswapV2DTLTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";

contract UniswapV2DirectToLiquidityOnCurateTest is UniswapV2DirectToLiquidityTest {
    uint96 internal constant _PAYOUT_AMOUNT = 1e18;

    // ============ Modifiers ============ //

    function _performCallback(uint96 lotId_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(lotId_, _PAYOUT_AMOUNT, false, abi.encode(""));
    }

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] when multiple lots are created
    //  [X] it marks the correct lot as inactive
    // [X] it registers the curator payout

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
        assertEq(configuration.lotCuratorPayout, _PAYOUT_AMOUNT, "lotCuratorPayout");

        // Check the balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(_baseToken.balanceOf(_NOT_SELLER), 0, "not seller base token balance");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY,
            "auction house base token balance"
        );
    }

    function test_success_multiple() public givenCallbackIsCreated givenOnCreate {
        uint96 lotIdOne = _lotId;

        // Create a second lot
        uint96 lotIdTwo = _createLot(_NOT_SELLER);

        // Call the function
        _performCallback(lotIdTwo);

        // Check the values
        BaseDirectToLiquidity.DTLConfiguration memory configurationOne =
            _getDTLConfiguration(lotIdOne);
        assertEq(configurationOne.lotCuratorPayout, 0, "lot one: lotCuratorPayout");

        BaseDirectToLiquidity.DTLConfiguration memory configurationTwo =
            _getDTLConfiguration(lotIdTwo);
        assertEq(configurationTwo.lotCuratorPayout, _PAYOUT_AMOUNT, "lot two: lotCuratorPayout");

        // Check the balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(_baseToken.balanceOf(_NOT_SELLER), 0, "not seller base token balance");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY * 2,
            "auction house base token balance"
        );
    }
}
