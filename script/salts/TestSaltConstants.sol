// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

abstract contract TestSaltConstants {
    address internal constant _OWNER = address(0x1);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);

    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0x1EBC400fd43aC56937d4e14B8495B0f021e7c876);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xE70b554757175BAb9eD3245C7f2b387ef09889Bd);
    address internal constant _GUNI_FACTORY = address(0x6c4f6A2E6b9AFB0406919979cE3570741BCb866A);
}
