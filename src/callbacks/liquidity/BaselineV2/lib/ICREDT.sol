// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice Individual credit account information per user
struct CreditAccount {
    uint256 credit; // Used to keep track of data in timeslots
    uint256 collateral; // bAsset collateral
    uint256 expiry; // Date when credit expires and collateral is defaulted
}

/// @notice Credit Module
interface ICREDTv1 {
    // --- STATE ---------------------------------------------------

    /// @notice bAsset token
    function bAsset() external view returns (ERC20);

    /// @notice Total reserves issued as credit
    function totalCreditIssued() external view returns (uint256);

    /// @notice Total bAssets collateralized
    function totalCollateralized() external view returns (uint256);

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
