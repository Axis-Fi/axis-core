/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

abstract contract TestConstants {
    address internal constant _OWNER = address(0x1);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAA349F4bA3f898eA8aa6C512bcE27DE3945Ce4B0);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA2c1Bf0600feef3Ab084283f016be75400d2aF3);
    address internal constant _GUNI_FACTORY = address(0xAAcb222Fb8050a78fEE1756a1E93F1A5D9dC4842);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA58516d932C482469914260268EEA7611BF0eb4);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
