// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

/// @title  IHooks
/// @notice Interface for hook contracts to be called during auction payment and payout
interface IHooks {
    /// @notice     Called before auction creation
    /// @notice     Requirements:
    ///             - If the lot is pre-funded, the hook must ensure that the auctioneer has the required balance of base tokens
    ///
    /// @param      lotId_              The auction's lot ID
    function preAuctionCreate(uint96 lotId_) external;

    /// @notice Called before payment and payout
    /// TODO define expected state, invariants
    function pre(uint96 lotId_, uint256 amount_) external;

    /// @notice Called after payment and before payout
    /// TODO define expected state, invariants
    function mid(uint96 lotId_, uint256 amount_, uint256 payout_) external;

    /// @notice Called after payment and after payout
    /// TODO define expected state, invariants
    function post(uint96 lotId_, uint256 payout_) external;
}
