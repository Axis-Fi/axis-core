/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

abstract contract TestConstants {
    address internal constant _OWNER = address(0x1);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAf6608Fd95c8aEF7BDdC4b34AaD8c8e3E2bCC45);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA553BdE34FDeC7D2e4A4449dc3d2B413c501476);
    address internal constant _GUNI_FACTORY = address(0xAAbEbD58513A48c433D1e4524F47aceaBFE980CB);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA75D0C0A81De6e0f0D944DCaf1b8D6fC6Bd58E1);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
