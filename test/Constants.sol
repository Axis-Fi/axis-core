/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

abstract contract TestConstants {
    address internal constant _OWNER = address(0x1);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAA951De23370B94938C97366Ad503EB159fe306D);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA67D5CbC449ee4FC8b07d86dE2D7a68EFF1bc04);
    address internal constant _GUNI_FACTORY = address(0xAA8EAef12a9cB93d7b06C855BE9d0665B0d311F8);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA58516d932C482469914260268EEA7611BF0eb4);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
