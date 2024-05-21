// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

contract BaselineOnCurateTest is BaselineAxisLaunchTest {
    // ============ Modifiers ============ //

    function _performCallback(uint256 curatorFee_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, curatorFee_, true, abi.encode(""));
    }

    // ============ Assertions ============ //

    // ============ Tests ============ //

    // [ ] when the lot has not been registered
    //  [ ] it reverts
    // [ ] when the caller is not the auction house
    //  [ ] it reverts
    // [ ] when the curator fee is non-zero
    //  [ ] it reverts
    // [ ] it does nothing
}
