// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library TimeslotLib {
    /// @notice uint256 is the unix timestamp at the end of the day
    /// @param timestamp_ Unix timestamp
    function getTimeslot(uint256 timestamp_) internal pure returns (uint256) {
        return timestamp_ - (timestamp_ % 1 days) + 1 days - 1;
    }

    function today() internal view returns (uint256) {
        return getTimeslot(block.timestamp);
    }

    function addDays(uint256 oldTimeslot_, uint256 numDays_) internal pure returns (uint256) {
        return getTimeslot(oldTimeslot_ + numDays_ * 1 days);
    }

    function subDays(uint256 oldTimeslot_, uint256 numDays_) internal pure returns (uint256) {
        return getTimeslot(oldTimeslot_ - numDays_ * 1 days);
    }

    function diffDays(uint256 from_, uint256 to_) internal pure returns (uint256) {
        if (from_ > to_) {
            return (from_ - to_) / 1 days;
        } else {
            return (to_ - from_) / 1 days;
        }
    }
}
