// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

/// @title      ICondenser
/// @notice     Interface for Condenser functionality
/// @dev        Condensers are used to modify auction output data into a format that can be understood by a derivative
interface ICondenser {
    /// @notice     Condense auction output data into a format that can be understood by a derivative
    ///
    /// @param      auctionOutput_      Output data from an auction
    /// @param      derivativeConfig_   Configuration data for the derivative
    /// @return     condensedOutput     Condensed output data
    function condense(
        bytes memory auctionOutput_,
        bytes memory derivativeConfig_
    ) external pure returns (bytes memory condensedOutput);
}
