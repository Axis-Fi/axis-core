// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAllowlist} from "src/bases/Auctioneer.sol";

contract MockAllowlist is IAllowlist {
    bool registerReverts = false;

    uint256[] public registeredIds;

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

    function register(uint256 id_, bytes calldata params_) external override {
        if (registerReverts) {
            revert("MockAllowlist: register reverted");
        }

        registeredIds.push(id_);
    }

    function setRegisterReverts(bool registerReverts_) external {
        registerReverts = registerReverts_;
    }

    function getRegisteredIds() external view returns (uint256[] memory) {
        return registeredIds;
    }
}
