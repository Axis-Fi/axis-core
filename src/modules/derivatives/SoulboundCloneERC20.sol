/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {CloneERC20} from "src/lib/clones/CloneERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title      SoulboundCloneERC20
/// @notice     A cloneable ERC20 token with the following additional features:
///             - Only the owner can mint/burn tokens
///             - Transfers and approvals are disabled
/// @dev        This contract can be cloned using the ClonesWithImmutableArgs.clone3(). The arguments required are:
///             - name (string)
///             - symbol (string)
///             - decimals (uint8)
///             - expiry (uint64)
///             - owner (address)
///             - underlying token (address)
contract SoulboundCloneERC20 is CloneERC20 {
    // ========== EVENTS ========== //

    // ========== ERRORS ========== //

    error NotPermitted();

    // ========== STATE VARIABLES ========== //

    // ========== CONSTRUCTOR ========== //

    // Constructor not supported when cloning

    // ========== OWNERSHIP ========== //

    modifier onlyOwner() {
        if (msg.sender != owner()) revert NotPermitted();
        _;
    }

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

    function approve(address, uint256) public pure override returns (bool) {
        revert NotPermitted();
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice     The timestamp at which the derivative can be redeemed for the underlying
    ///
    /// @return     The expiry timestamp
    function expiry() external pure returns (uint48) {
        return uint48(_getArgUint64(0x41)); // decimals offset (64) + 1 byte
    }

    /// @notice     The address of the owner of the derivative
    ///
    /// @return     The address of the owner
    function owner() public pure returns (address) {
        return _getArgAddress(0x49); // expiry offset + 8 bytes
    }

    /// @notice     The token to be redeemed when the derivative is vested
    ///
    /// @return     The address of the underlying token
    function underlying() external pure returns (ERC20) {
        return ERC20(_getArgAddress(0x5D)); // owner offset + 20 bytes
    }
}
