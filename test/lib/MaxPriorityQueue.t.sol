// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {MaxPriorityQueue, Queue, BidEncoding} from "src/lib/MaxPriorityQueue.sol";

contract EmpaMaxPriorityQueueTest is Test {
    using MaxPriorityQueue for Queue;

    Queue internal _queue;

    bytes32 internal constant QUEUE_START =
        0x0000000000000000ffffffffffffffffffffffff000000000000000000000001;
    // bytes32 internal constant QUEUE_END =
    //     0xffffffffffffffff000000000000000000000000000000000000000000000001;

    // [X] when added in ascending order
    // [X] when a single bid is added
    // [X] when a larger bid is added
    //  [X] it sorts in ascending order
    // [X] when a bid is added in the middle
    //  [X] it adds it to the middle
    // [X] duplicate bid id
    // TODO additional tests for new library features and edge cases

    function test_insertAscendingPrice() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 0, 1, 1);
        _queue.insert(QUEUE_START, 1, 2, 1);
        _queue.insert(QUEUE_START, 2, 3, 1);

        // Check values
        assertEq(_queue.getNumBids(), 3);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 2);
        assertEq(amountIn, 3);
        assertEq(amountOut, 1);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 2);
        assertEq(amountOut, 1);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 1);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_singleBid() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 0, 1, 1);

        // Check values
        assertEq(_queue.getNumBids(), 1);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 1);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_addLargerBid() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 0, 1, 1);
        _queue.insert(QUEUE_START, 1, 4, 2);

        // Check values
        assertEq(_queue.getNumBids(), 2);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 4);
        assertEq(amountOut, 2);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 1);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_addBidSamePrice() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 1, 2, 1);
        bytes32 prevHint = BidEncoding.encode(1, 2, 1);
        _queue.insert(prevHint, 2, 4, 2);

        // Check values
        assertEq(_queue.getNumBids(), 2);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 2);
        assertEq(amountOut, 1);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 2);
        assertEq(amountIn, 4);
        assertEq(amountOut, 2);

        assertEq(_queue.isEmpty(), true);
    }

    function test_addBidSamePrice_reverse() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 1, 4, 2);
        bytes32 prevHint = BidEncoding.encode(1, 4, 2);
        _queue.insert(prevHint, 2, 2, 1);

        // Check values
        assertEq(_queue.getNumBids(), 2);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 4);
        assertEq(amountOut, 2);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 2);
        assertEq(amountIn, 2);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_addBidInMiddle() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 0, 1, 1);
        _queue.insert(QUEUE_START, 1, 3, 1);
        bytes32 prevHint = BidEncoding.encode(1, 3, 1);
        _queue.insert(prevHint, 2, 2, 1);

        // Check values
        assertEq(_queue.getNumBids(), 3);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 3);
        assertEq(amountOut, 1);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 2);
        assertEq(amountIn, 2);
        assertEq(amountOut, 1);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 1);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_duplicateBidId() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 0, 1, 1);
        _queue.insert(QUEUE_START, 0, 3, 1);

        // Check values
        assertEq(_queue.getNumBids(), 2, "numBids mismatch");

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 3);
        assertEq(amountOut, 1);

        // Should still work because the keys are still unique
        // Not intended to be used this way though
        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 1);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true, "isEmpty mismatch");
    }

    function test_zeroAmountIn() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 0, 0, 1);
        _queue.insert(QUEUE_START, 1, 1, 1);

        // Check values
        assertEq(_queue.getNumBids(), 2, "numBids mismatch");

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 1);
        assertEq(amountOut, 1);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 0);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true, "isEmpty mismatch");
    }

    function test_zeroAmountOut_reverts() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 1, 1, 1);

        vm.expectRevert();
        _queue.insert(QUEUE_START, 0, 1, 0);
    }

    function test_largeNumber() external {
        _queue.initialize();

        _queue.insert(QUEUE_START, 0, 1e18, 1e18);
        _queue.insert(QUEUE_START, 1, 2e18, 1e18);

        // Check values
        assertEq(_queue.getNumBids(), 2, "numBids mismatch");

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 2e18);
        assertEq(amountOut, 1e18);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 1e18);
        assertEq(amountOut, 1e18);
    }
}
