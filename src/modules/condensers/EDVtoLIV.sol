// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {CondenserModule} from "src/modules/Condenser.sol";
import {Module} from "src/modules/Modules.sol";
import {Veecode, toVeecode} from "src/modules/Keycode.sol";
import {ILinearVesting} from "src/interfaces/modules/derivatives/ILinearVesting.sol";

contract EDVtoLIV is CondenserModule {
    // ========== SETUP ========== //

    constructor(address auctionHouse_) Module(auctionHouse_) {}

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01EVLVC");
    }

    // ========== CONDENSER ========== //

    function condense(
        bytes memory auctionOutput_,
        bytes memory derivativeConfig_
    ) external pure override returns (bytes memory condensedOutput) {
        // Auction output is a vesting duration
        uint128 vestingDuration = abi.decode(auctionOutput_, (uint128));

        // Derivative config is a start timestamp for the vesting token
        uint48 start = abi.decode(derivativeConfig_, (uint48));

        // We cap the vesting duration to the max uint48 value
        uint48 duration =
            vestingDuration > type(uint48).max ? type(uint48).max : uint48(vestingDuration);

        // Calculate the expiry from the start time and duration
        uint48 expiry = start + duration;

        // Condensed output is the required linear vesting params
        return abi.encode(ILinearVesting.VestingParams(start, expiry));
    }
}
