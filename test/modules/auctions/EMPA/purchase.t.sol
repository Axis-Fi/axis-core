// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

contract EmpaModulePurchaseTest is EmpaModuleTest {
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
