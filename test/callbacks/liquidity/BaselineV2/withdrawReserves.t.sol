// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from
    "test/callbacks/liquidity/BaselineV2/BaselineAxisLaunchTest.sol";

contract BaselineWithdrawReservesTest is BaselineAxisLaunchTest {
    // ============ Tests ============ //

    // [X] when the caller is not the owner
    //  [X] it reverts
    // [X] when there are no reserves
    //  [X] it returns 0
    // [X] it transfers the reserves to the owner

    function test_notOwner_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAddressHasBaseTokenBalance(_dtlAddress, 1e18)
    {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Perform callback
        vm.prank(_BUYER);
        _dtl.withdrawReserves();
    }

    function test_noReserves_returnsZero() public givenBPoolIsCreated givenCallbackIsCreated {
        // Perform callback
        vm.prank(_OWNER);
        uint256 reserves = _dtl.withdrawReserves();

        // Assert reserves
        assertEq(reserves, 0, "reserves withdrawn");
    }

    function test_success()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAddressHasQuoteTokenBalance(_dtlAddress, 1e18)
    {
        // Perform callback
        vm.prank(_OWNER);
        uint256 reserves = _dtl.withdrawReserves();

        // Assert reserves
        assertEq(reserves, 1e18, "reserves withdrawn");

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(_OWNER), 1e18, "quote token: this");
    }
}
