/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Owned} from "solmate/auth/Owned.sol";
import {CloneERC20} from "src/lib/clones/CloneERC20.sol";

/// @title      SoulboundCloneERC20
/// @notice     A cloneable ERC20 token with the following additional features:
///             - Only the owner can mint/burn tokens
///             - Transfers are disabled
contract SoulboundCloneERC20 is CloneERC20, Owned {
    error NotPermitted();

    // ========== EVENTS ========== //

    // ========== STATE VARIABLES ========== //

    // ========== CONSTRUCTOR ========== //

    constructor() Owned(msg.sender) {}

    // ========== GATED FUNCTIONS ========== //

    /// @notice     Mint new tokens
    /// @dev        Only callable by the owner
    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }

    /// @notice     Burn tokens
    /// @dev        Only callable by the owner
    function burn(address from_, uint256 amount_) external onlyOwner {
        _burn(from_, amount_);
    }

    // ========== TRANSFER FUNCTIONS ========== //

    function transfer(address, uint256) public pure override returns (bool) {
        revert NotPermitted();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert NotPermitted();
    }

    // TODO approval disabled?
}
