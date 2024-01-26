// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

// RSA
import {RSAOAEP} from "src/lib/RSA.sol";

contract RSAOAEPTest is Test {
    bytes internal constant E = abi.encodePacked(uint24(65_537));

    function setUp() external {}

    // TODO more extensive cases
    // TODO fuzz value to encrypt

    function test_roundTrip(uint256 seed_) external {
        uint256 value = 5 * 10 ** 18;
        bytes memory message = abi.encodePacked(value);
        bytes memory label = abi.encodePacked(uint96(1));

        bytes memory n = abi.encodePacked(
            bytes32(0xB925394F570C7C765F121826DFC8A1661921923B33408EFF62DCAC0D263952FE),
            bytes32(0x158C12B2B35525F7568CB8DC7731FBC3739F22D94CB80C5622E788DB4532BD8C),
            bytes32(0x8643680DA8C00A5E7C967D9D087AA1380AE9A031AC292C971EC75F9BD3296AE1),
            bytes32(0x1AFCC05BD15602738CBE9BD75B76403AB2C9409F2CC0C189B4551DEE8B576AD3)
        );

        bytes memory d = abi.encodePacked(
            bytes32(0x931e0d080a77957ec9d4aaf458e627b9e54653d84ec581db55475c3fa69bee62),
            bytes32(0x8fe49a06fd912f75f6842370ac163fa3f3800444ff3d503031d4215f7b00f2b4),
            bytes32(0x183c2b8191ee422acad2b6b29c26d8ba6b2dba73fe839fc4a1b180f5aa7e3723),
            bytes32(0x0376dbb6b9571938f796fdcc3b4687f791a1d14c1a578890cdb2f4413a413ba1)
        );

        bytes memory encrypted = RSAOAEP.encrypt(message, label, E, n, seed_);

        (bytes memory decrypted, bytes32 returnedSeed) = RSAOAEP.decrypt(encrypted, d, n, label);

        uint256 returnedValue = abi.decode(decrypted, (uint256));

        assertEq(returnedValue, value);
        assertEq(returnedSeed, sha256(abi.encodePacked(seed_)));
    }
}
