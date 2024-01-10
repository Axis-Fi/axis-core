// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAllowlist} from "src/bases/Auctioneer.sol";

contract MockAllowlist is IAllowlist {
    function isAllowed(
        address user_,
        bytes calldata proof_
    ) external view override returns (bool) {}

    function isAllowed(
        uint256 id_,
        address user_,
        bytes calldata proof_
    ) external view override returns (bool) {}

    function register(bytes calldata params_) external override {}

    function register(uint256 id_, bytes calldata params_) external override {}
}
