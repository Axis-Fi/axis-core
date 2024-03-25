// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";

import {EmpModuleTest} from "test/modules/auctions/EMP/EMPModuleTest.sol";

contract EmpaModulePurchaseTest is EmpModuleTest {
    // [X] it reverts

    function test_reverts() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(_auctionHouse));
        _module.purchase(_lotId, 1e18, abi.encode(""));
    }
}
