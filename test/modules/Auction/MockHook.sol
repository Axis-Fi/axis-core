// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IHooks} from "src/bases/Auctioneer.sol";

contract MockHook is IHooks {
    function dummy() external pure {
        //
    }
}
