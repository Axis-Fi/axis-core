/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

abstract contract TestConstants {
    address internal constant _OWNER = address(0x1);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0x584A2a1F5eCdCDcB6c0616cd280a7Db89239872B);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA5112f28f20a28907a1754927c556dADE865ed4);
    address internal constant _GUNI_FACTORY = address(0xAA9E05BB6ee2880a5c6127F486BCb4D624863dD6);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA58516d932C482469914260268EEA7611BF0eb4);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
