// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {UD60x18} from "lib/prb-math/src/UD60x18.sol";
import {IAtomicAuction} from "src/interfaces/modules/IAtomicAuction.sol";

/// @notice Interface for gradual dutch (atomic) auctions
interface IGradualDutchAuction is IAtomicAuction {
    // ========== ERRORS ========== //

    error GDA_InvalidParams(uint256 step); // the step tells you where the error occurred

    // ========== DATA STRUCTURES ========== //

    /// @notice Auction pricing data
    /// @param equilibriumPrice The initial price of one base token, where capacity and time are balanced
    /// @param minimumPrice The minimum price for one base token
    /// @param lastAuctionStart The time that the last un-purchased auction started, may be in the future
    /// @param decayConstant The speed at which the price decays, as UD60x18
    /// @param emissionsRate The number of tokens released per day, as UD60x18. Calculated as capacity / duration (in days)
    struct AuctionData {
        uint256 equilibriumPrice;
        uint256 minimumPrice;
        uint256 lastAuctionStart;
        UD60x18 decayConstant;
        UD60x18 emissionsRate;
    }

    /// @notice Parameters to create a GDA
    /// @param equilibriumPrice The initial price of one base token, where capacity and time are balanced
    /// @param minimumPrice The minimum price for one base token
    /// @param decayTarget The target decay percent over the first decay period of an auction (steepest part of the curve)
    /// @param decayPeriod The period over which the target decay percent is reached, in seconds
    struct GDAParams {
        uint256 equilibriumPrice; // initial price of one base token, where capacity and time are balanced
        uint256 minimumPrice; // minimum price for one base token
        uint256 decayTarget; // target decay percent over the first decay period of an auction (steepest part of the curve)
        uint256 decayPeriod; // period over which the target decay percent is reached, in seconds
    }

    // ========== STATE VARIABLES ========== //

    /// @notice Returns the `AuctionData` for a lot
    ///
    /// @param  lotId       The lot ID
    function auctionData(uint96 lotId)
        external
        view
        returns (uint256, uint256, uint256, UD60x18, UD60x18);
}
