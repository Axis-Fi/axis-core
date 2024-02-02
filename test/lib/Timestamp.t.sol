// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

import {Timestamp} from "src/lib/Timestamp.sol";

contract TimestampTest is Test {
    using Timestamp for uint48;

    function test_toPaddedString_leadingZeroes() public {
        uint48 timestamp = 1_707_042_344; // 2024-02-04 10:25:44 GMT

        (string memory year, string memory month, string memory day) = timestamp.toPaddedString();
        assertEq(year, "2024");
        assertEq(month, "02");
        assertEq(day, "04");
    }

    function test_toPaddedString() public {
        uint48 timestamp = 1_730_370_344; // 2024-10-31 10:25:44 GMT

        (string memory year, string memory month, string memory day) = timestamp.toPaddedString();
        assertEq(year, "2024");
        assertEq(month, "10");
        assertEq(day, "31");
    }
}
