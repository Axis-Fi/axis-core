// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice Individual credit account information per user
struct CreditAccount {
    uint256 credit; // Used to keep track of data in timeslots
    uint256 collateral; // bAsset collateral
    uint256 expiry; // Date when credit expires and collateral is defaulted
}

/// @notice Baseline Credit Module
/// @dev    Imported at commit 88bb34b23b1627207e4c8d3fcd9efad22332eb5f
interface ICREDTv1 {
    // --- STATE ---------------------------------------------------

    /// @notice bAsset token
    function bAsset() external view returns (ERC20);

    /// @notice Individual credit account state
    function creditAccounts(address)
        external
        view
        returns (uint256 credit, uint256 collateral, uint256 expiry);

    /// @notice Container for aggregate credit and collateral to be defaulted at a timeslot
    struct Defaultable {
        uint256 credit; // Total reserves issued for this timeslot
        uint256 collateral; // Total bAssets collateralized for this timeslot
    }

    /// @notice List of aggregate credits and collateral that must be defaulte when a timeslot is reached
    function defaultList(uint256) external view returns (uint256 credit, uint256 collateral);

    /// @notice Last timeslot that was defaulted, acts as queue iterator
    function lastDefaultedTimeslot() external view returns (uint256);

    /// @notice Total reserves issued as credit
    function totalCreditIssued() external view returns (uint256);

    /// @notice Total bAssets collateralized
    function totalCollateralized() external view returns (uint256);

    /// @notice Total interest accrued
    function totalInterestAccumulated() external view returns (uint256);

    // --- EXTERNAL FUNCTIONS --------------------------------------------

    /// @notice Gets current credit account for user.
    /// @dev    Returns zeroed account after full repayment or default.
    function getCreditAccount(address _user)
        external
        view
        returns (CreditAccount memory account_);

    function updateCreditAccount(
        address _user,
        uint256 _newCollateral,
        uint256 _newCredit,
        uint256 _newInterest,
        uint256 _newExpiry
    ) external;
}
