// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Testing Libraries
import {ECIESFFITest} from "./ECIES_FFI.sol";
import {console2} from "forge-std/console2.sol";

contract SaltTest is ECIESFFITest {
    function test_salt() public {
        // Setup salt parameters
        uint96 lotId = 1;
        address bidder = address(this);
        uint96 amount = 1e18;

        // Generate the salt locally
        uint256 expectedSalt = uint256(keccak256(abi.encodePacked(lotId, bidder, amount)));
        console2.log("Expected Salt", expectedSalt);

        // Generate the salt using the FFI
        uint256 salt = _salt(lotId, bidder, amount);
        console2.log("FFI salt", salt);

        // Compare the generated salts
        assertEq(expectedSalt, salt);
    }

    function testFuzz_salt(uint96 lotId_, address bidder_, uint96 amount_) public {
        // Generate the salt locally
        uint256 expectedSalt = uint256(keccak256(abi.encodePacked(lotId_, bidder_, amount_)));

        // Generate the salt using the FFI
        uint256 salt = _salt(lotId_, bidder_, amount_);

        // Compare the generated salts
        assertEq(expectedSalt, salt);
    }
}
