// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IHooks} from "src/bases/Auctioneer.sol";

contract MockHook is IHooks {
    bool public preHookReverts;

    function pre(uint256 lotId_, uint256 amount_) external override {}

    function setPreHookReverts(bool preHookReverts_) external {
        preHookReverts = preHookReverts_;
    }

    function mid(uint256 lotId_, uint256 amount_, uint256 payout_) external override {}

    function post(uint256 lotId_, uint256 payout_) external override {}
}
