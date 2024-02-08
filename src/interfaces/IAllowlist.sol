// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IAllowlist {
    /// @notice         Check if address is allowed to interact with lot ID on sending contract
    /// @param lotId_   Lot ID to check
    /// @param user_    Address to check
    /// @param proof_   Data to be used in determining allow status (optional, depends on specific implementation
    /// @return         True if allowed, false otherwise
    function isAllowed(
        uint96 lotId_,
        address user_,
        bytes calldata proof_
    ) external view returns (bool);

    /// @notice         Register allowlist for lot ID on sending address
    /// @dev            Can be used to intialize or update an allowlist
    /// @param lotId_   Lot ID to register allowlist for
    /// @param params_  Parameters to configure allowlist (depends on specific implementation)
    function register(uint96 lotId_, bytes calldata params_) external;
}
