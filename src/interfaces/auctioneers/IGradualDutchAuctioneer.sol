// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {IAuctioneer} from "src/interfaces/IAuctioneer.sol";
import {SD59x18} from "prb-math/SD59x18.sol";

interface IGradualDutchAuctioneer is IAuctioneer {
    enum Decay {
        Linear,
        Exponential
    } // TODO Logistic?

    /// @notice Auction pricing data
    struct AuctionData {
        uint256 equilibriumPrice; // price at which the auction is balanced
        uint256 scale;
        uint48 lastAuctionStart;
        Decay decayType; // type of decay to use for the market
        SD59x18 decayConstant; // speed at which the price decays, as SD59x18.
        SD59x18 emissionsRate; // number of tokens released per second, as SD59x18. Calculated as capacity / duration.
    }
}
