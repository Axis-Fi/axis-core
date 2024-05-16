// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {ICatalogue} from "src/interfaces/ICatalogue.sol";

/// @title  IAtomicCatalogue
/// @notice Interface for the AtomicCatalogue contract, which provides view functions for atomic auctions
interface IAtomicCatalogue is ICatalogue {
    /// @notice     Returns the payout for a given lot and amount
    ///
    /// @param      lotId_      ID of the auction lot
    /// @param      amount_     Amount of quoteToken to purchase with (in native decimals)
    /// @return     payout      Amount of baseToken (in native decimals) to be received by the buyer
    function payoutFor(uint96 lotId_, uint256 amount_) external view returns (uint256 payout);

    /// @notice     Returns the price for a given lot and payout
    ///
    /// @param      lotId_      ID of the auction lot
    /// @param      payout_     Amount of baseToken (in native decimals) to be received by the buyer
    /// @return     price       The purchase price in terms of the quote token
    function priceFor(uint96 lotId_, uint256 payout_) external view returns (uint256 price);

    /// @notice     Returns the max payout for a given lot
    ///
    /// @param      lotId_      ID of the auction lot
    /// @return     payout      The maximum amount of baseToken (in native decimals) that can be received by the buyer
    function maxPayout(uint96 lotId_) external view returns (uint256 payout);

    /// @notice     Returns the max amount accepted for a given lot
    ///
    /// @param      lotId_      ID of the auction lot
    /// @return     maxAmount   The maximum amount of quoteToken (in native decimals) that can be accepted by the auction
    function maxAmountAccepted(uint96 lotId_) external view returns (uint256 maxAmount);
}
