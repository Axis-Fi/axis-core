// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

contract BaselineOnCancelTest is BaselineAxisLaunchTest {
    // ============ Modifiers ============ //

    // ============ Assertions ============ //

    // ============ Tests ============ //

    // [ ] when the lot has not been registered
    //  [ ] it reverts
    // [ ] when the caller is not the auction house
    //  [ ] it reverts
    // [ ] when the lot has already been cancelled
    //  [ ] it reverts
    // [ ] when an insufficient quantity of the base token is transferred to the callback
    //  [ ] it reverts
    // [ ] it updates circulating supply, marks the auction as completed and burns the refunded base token quantity
}
