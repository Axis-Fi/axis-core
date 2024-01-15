// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAllowlist} from "src/bases/Auctioneer.sol";

contract MockAllowlist is IAllowlist {
    bool registerReverts = false;

    uint256[] public registeredIds;

    mapping(address => bool) public allowed;

    function isAllowed(address address_, bytes calldata) external view override returns (bool) {
        return allowed[address_];
    }

    function isAllowed(
        uint256,
        address address_,
        bytes calldata
    ) external view override returns (bool) {
        return allowed[address_];
    }

    function register(bytes calldata) external override {}

    function register(uint256 id_, bytes calldata) external override {
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

    function setAllowed(address account, bool allowed_) external {
        allowed[account] = allowed_;
    }
}
