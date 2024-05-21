// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

contract BaselineOnSettleTest is BaselineAxisLaunchTest {
    uint256 internal constant _PROCEEDS_AMOUNT = 20e18;
    uint256 internal constant _REFUND_AMOUNT = 2e18;

    // ============ Modifiers ============ //

    function _performCallback() internal {
        vm.prank(address(_auctionHouse));
        _dtl.onSettle(_lotId, _PROCEEDS_AMOUNT, _REFUND_AMOUNT, abi.encode(""));
    }

    // ============ Assertions ============ //

    // ============ Tests ============ //

    // [ ] when the lot has not been registered
    //  [ ] it reverts
    // [ ] when the caller is not the auction house
    //  [ ] it reverts
    // [ ] when the lot has already been settled
    //  [ ] it reverts
    // [ ] when the lot has already been cancelled
    //  [ ] it reverts
    // [ ] when insufficient proceeds are sent to the callback
    //  [ ] it reverts
    // [ ] when insufficient refund is sent to the callback
    //  [ ] it reverts
    // [ ] given the auction format is EMPA
    //  [ ] it performs the standard behaviour and sets the anchor tick based on the auction marginal price
    // [ ] it burns refunded base tokens, updates the circulating supply, marks the auction as completed and deploys the reserves into the Baseline pool
}
