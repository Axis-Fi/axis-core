// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {ICatalogue} from "src/interfaces/ICatalogue.sol";

interface IAtomicCatalogue is ICatalogue {
    /// @notice     Returns the payout for a given lot and amount
    function payoutFor(uint96 lotId_, uint256 amount_) external view returns (uint256);

    /// @notice     Returns the price for a given lot and payout
    function priceFor(uint96 lotId_, uint256 payout_) external view returns (uint256);

    /// @notice     Returns the max payout for a given lot
    function maxPayout(uint96 lotId_) external view returns (uint256);

    /// @notice     Returns the max amount accepted for a given lot
    function maxAmountAccepted(uint96 lotId_) external view returns (uint256);
}
