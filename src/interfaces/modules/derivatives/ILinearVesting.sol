// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

/// @title  ILinearVesting
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

    /// @notice     Format for the vesting data, stored in `Token.data`
    ///
    /// @param      start       The timestamp at which the vesting starts
    /// @param      expiry      The timestamp at which the vesting expires
    struct VestingParams {
        uint48 start;
        uint48 expiry;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice     Get the vesting parameters for a derivative token
    ///
    /// @param      tokenId         The ID of the derivative token
    /// @return     vestingParams   The vesting parameters
    function getTokenVestingParams(uint256 tokenId)
        external
        view
        returns (VestingParams memory vestingParams);
}
