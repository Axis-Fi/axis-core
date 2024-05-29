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
        address(0xAAD7BEa01E58E31458De2B02f41fFc676Eaa25De);
    address internal constant _GUNI_FACTORY = address(0xAA02456e20BB6840c05DA9359420b9467E5BC504);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA28371dF86cA8FAAd96a3999f7b20C0d80A2835);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
