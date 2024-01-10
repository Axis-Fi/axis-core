// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

/// @title  IHooks
/// @notice Interface for hook contracts to be called during auction payment and payout
interface IHooks {
    /// @notice Called before payment and payout
    function pre(uint256 lotId_, uint256 amount_) external;

    /// @notice Called after payment and before payout
    function mid(uint256 lotId_, uint256 amount_, uint256 payout_) external;

    /// @notice Called after payment and after payout
    function post(uint256 lotId_, uint256 payout_) external;
}
