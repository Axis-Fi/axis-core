// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

/// @notice Interface for a linear vesting derivative
/// @dev    This contract does not inherit from `IDerivative` in order to avoid conflicts. Implementing contracts should inherit from both `DerivativeModule` (or `IDerivative`) and this interface.
interface ILinearVesting {
    // ========== EVENTS ========== //

    event DerivativeCreated(
        uint256 indexed tokenId, uint48 start, uint48 expiry, address baseToken
    );

    event WrappedDerivativeCreated(uint256 indexed tokenId, address wrappedToken);

    event Wrapped(
        uint256 indexed tokenId, address indexed owner, uint256 amount, address wrappedToken
    );

    event Unwrapped(
        uint256 indexed tokenId, address indexed owner, uint256 amount, address wrappedToken
    );

    event Redeemed(uint256 indexed tokenId, address indexed owner, uint256 amount);

    // ========== ERRORS ========== //

    error BrokenInvariant();
    error InsufficientBalance();
    error NotPermitted();
    error InvalidParams();
    error UnsupportedToken(address token_);

    // ========== DATA STRUCTURES ========== //

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting starts
    /// @param      expiry      The timestamp at which the vesting expires
    /// @param      baseToken   The address of the base token
    struct VestingData {
        uint48 start;
        uint48 expiry;
        address baseToken;
    }

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting starts
    /// @param      expiry      The timestamp at which the vesting expires
    struct VestingParams {
        uint48 start;
        uint48 expiry;
    }
}
