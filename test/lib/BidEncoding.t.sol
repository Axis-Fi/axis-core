// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {BidEncoding} from "src/lib/MaxPriorityQueue.sol";

contract BidEncodingTest is Test {
    using BidEncoding for bytes32;

    // [X] encode
    //     [X] encodes the bidId, amountIn, and minAmountOut correctly into a bytes32
    // [X] decode
    //     [X] decodes the bidId, amountIn, and minAmountOut correctly from a bytes32
    // [X] isHigherPriorityThan
    //     [X] returns true when
    //         [X] the first bid has a higher price than the second bid
    //         [X] the first bid has the same price and lower id than the second bid
    //     [X] returns false when
    //         [X] the first bid has a lower price than the second bid
    //         [X] the first bid has the same price and higher id than the second bid

    // ========== encode ========== //

    function testFuzz_encode(uint64 bidId, uint96 amountIn, uint96 amountOut) public {
        bytes32 encoded = BidEncoding.encode(bidId, amountIn, amountOut);
        bytes32 expected =
            bytes32(uint256(bidId) << 192 | uint256(amountIn) << 96 | uint256(amountOut));

        assertEq(encoded, expected);
    }

    // ========== decode ========== //

    function testFuzz_decode(bytes32 key) public {
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = key.decode();

        uint64 eId = uint64(uint256(key >> 192));
        uint96 eAmountIn = uint96(uint256(key >> 96));
        uint96 eAmountOut = uint96(uint256(key));

        assertEq(bidId, eId, "id mismatch");
        assertEq(amountIn, eAmountIn, "amountIn mismatch");
        assertEq(amountOut, eAmountOut, "amountOut mismatch");
    }

    // ========== isHigherPriorityThan ========== //

    function testFuzz_isHigherPriorityThan_firstHigherPrice(
        uint96 aAmountIn,
        uint96 aAmountOut,
        uint96 bAmountIn,
        uint96 bAmountOut
    ) external pure {
        vm.assume(
            uint256(aAmountIn) * uint256(bAmountOut) > uint256(bAmountIn) * uint256(aAmountOut)
        );

        bytes32 a = BidEncoding.encode(0, aAmountIn, aAmountOut);
        bytes32 b = BidEncoding.encode(1, bAmountIn, bAmountOut);

        bool result = BidEncoding.isHigherPriorityThan(a, b);
        assert(result);

        a = BidEncoding.encode(1, aAmountIn, aAmountOut);
        b = BidEncoding.encode(0, bAmountIn, bAmountOut);

        result = BidEncoding.isHigherPriorityThan(a, b);
        assert(result);

        a = BidEncoding.encode(0, aAmountIn, aAmountOut);
        b = BidEncoding.encode(0, bAmountIn, bAmountOut);

        result = BidEncoding.isHigherPriorityThan(a, b);
        assert(result);
    }

    function test_isHigherPriorityThan_samePrice() external pure {
        uint96 aAmountIn = uint96(10e18);
        uint96 aAmountOut = uint96(1e18);
        uint96 bAmountIn = uint96(20e18);
        uint96 bAmountOut = uint96(2e18);

        bytes32 a = BidEncoding.encode(0, aAmountIn, aAmountOut);
        bytes32 b = BidEncoding.encode(1, bAmountIn, bAmountOut);

        bool result = BidEncoding.isHigherPriorityThan(a, b);
        assert(result);

        a = BidEncoding.encode(1, aAmountIn, aAmountOut);
        b = BidEncoding.encode(0, bAmountIn, bAmountOut);

        result = BidEncoding.isHigherPriorityThan(a, b);
        assert(!result);
    }

    function testFuzz_isHigherPriorityThan_secondPriceHigher(
        uint96 aAmountIn,
        uint96 aAmountOut,
        uint96 bAmountIn,
        uint96 bAmountOut
    ) external pure {
        vm.assume(
            uint256(aAmountIn) * uint256(bAmountOut) < uint256(bAmountIn) * uint256(aAmountOut)
        );

        bytes32 a = BidEncoding.encode(0, aAmountIn, aAmountOut);
        bytes32 b = BidEncoding.encode(1, bAmountIn, bAmountOut);

        bool result = BidEncoding.isHigherPriorityThan(a, b);
        assert(!result);

        a = BidEncoding.encode(1, aAmountIn, aAmountOut);
        b = BidEncoding.encode(0, bAmountIn, bAmountOut);

        result = BidEncoding.isHigherPriorityThan(a, b);
        assert(!result);

        a = BidEncoding.encode(0, aAmountIn, aAmountOut);
        b = BidEncoding.encode(0, bAmountIn, bAmountOut);

        result = BidEncoding.isHigherPriorityThan(a, b);
        assert(!result);
    }
}