// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "@forge-std-1.9.1/Test.sol";

// Mocks
import {MockAtomicAuctionModule} from "./MockAtomicAuctionModule.sol";
import {Permit2User} from "../../lib/permit2/Permit2User.sol";

// Auctions
import {AuctionModule} from "../../../src/modules/Auction.sol";
import {AtomicAuctionHouse} from "../../../src/AtomicAuctionHouse.sol";

// Modules
import {Module} from "../../../src/modules/Modules.sol";

contract SetMinAuctionDurationTest is Test, Permit2User {
    MockAtomicAuctionModule internal _mockAuctionModule;
    AtomicAuctionHouse internal _auctionHouse;
    address internal constant _PROTOCOL = address(0x2);

    function setUp() external {
        // Ensure the block timestamp is a sane value
        vm.warp(1_000_000);

        _auctionHouse = new AtomicAuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _mockAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));

        _auctionHouse.installModule(_mockAuctionModule);
    }

    // [X] when the caller is not the auction house owner
    //  [X] it reverts
    // [X] when the caller is using execOnModule
    //  [X] it sets the min auction duration
    // [X] when the caller is the auction house
    //  [X] it sets the min auction duration

    function test_notOwner_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _mockAuctionModule.setMinAuctionDuration(1);
    }

    function test_execOnModule() public {
        // Call the function
        _auctionHouse.execOnModule(
            _mockAuctionModule.VEECODE(),
            abi.encodeWithSelector(AuctionModule.setMinAuctionDuration.selector, 1)
        );

        // Check values
        assertEq(_mockAuctionModule.minAuctionDuration(), 1);
    }

    function test_auctionHouse() public {
        // Call the function
        vm.prank(address(_auctionHouse));
        _mockAuctionModule.setMinAuctionDuration(1);

        // Check values
        assertEq(_mockAuctionModule.minAuctionDuration(), 1);
    }
}
