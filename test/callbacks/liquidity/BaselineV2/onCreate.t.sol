// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

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
    }

    // ============ Tests ============ //

    // [ ] when the callback data is incorrect
    //  [ ] it reverts
    // [ ] when the callback is not called by the auction house
    //  [ ] it reverts
    // [ ] when the lot has already been registered
    //  [ ] it reverts
    // [ ] when the base token is not the BPOOL
    //  [ ] it reverts
    // [ ] when the quote token is not the reserve
    //  [ ] it reverts
    // [ ] when the percentReservesFloor is 0
    //  [ ] it reverts
    // [ ] when the percentReservesFloor is > 100%
    //  [ ] it reverts
    // [ ] when the anchorTickWidth is 0
    //  [ ] it reverts
    // [ ] when the discoveryTickWidth is 0
    //  [ ] it reverts
    // [ ] when the auction format is not EMP or FPB
    //  [ ] it reverts
    // [ ] when the auction is not prefunded
    //  [ ] it reverts
    // [ ] when the auction format is FPB
    //  [ ] when the initAnchorTick is 0
    //   [ ] it reverts
    //  [ ] when the initAnchorTick is not a multiple of the tick spacing
    //   [ ] it rounds to the nearest multiple of the tick spacing
    //  [ ] when the anchorTickWidth is narrow
    //   [ ] it correctly sets the floor ticks to not overlap with the anchor ticks
    //  [ ] when the discoveryTickWidth is narrow
    //   [ ] it correctly sets the discovery ticks to not overlap with the anchor ticks
    //  [ ] it performs the standard behaviour, plus initializes the pool and sets the range ticks
    // [ ] it transfers the base token to the auction house, updates circulating supply, sets the state variables
}
