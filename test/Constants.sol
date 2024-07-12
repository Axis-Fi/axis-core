/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

abstract contract TestConstants {
    address internal constant _OWNER = address(0x1);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAe2b0bEf00E78705673DFc5c3a8Fb39Dba6E3E5);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA70C9Ef2969368cE15644696b63b0fcEb93e501);
    address internal constant _GUNI_FACTORY = address(0xAA6180e11cf2118E9e9D766D67Bb8Bb9959DF17B);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA35Ed8EbB48Ab6582F2aF7E0FF6819119fEdCb8);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
