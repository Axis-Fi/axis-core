// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

contract BaselineOnSettleTest is BaselineAxisLaunchTest {
    // ============ Modifiers ============ //

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
    // [ ] it burns refunded base tokens, updates the circulating supply, marks the auction as completed and deploys the reserves into the Baseline pool
}
