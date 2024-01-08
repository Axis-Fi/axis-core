// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

// Auctions
import {AuctionHouse} from "src/AuctionHouse.sol";

contract AuctionTest is Test {
    MockERC20 baseToken;
    MockERC20 quoteToken;
    AuctionHouse auctionHouse;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse();
    }
}
