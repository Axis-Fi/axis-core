// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {MaxPriorityQueue, Queue, Bid} from "src/lib/MaxPriorityQueue.sol";

contract EmpaMaxPriorityQueueTest is Test {
    using MaxPriorityQueue for Queue;

    Queue internal _queue;

    // [X] when added in ascending order
    // [X] when a single bid is added
    // [X] when a larger bid is added
    //  [X] it sorts in ascending order
    // [X] when a bid is added in the middle
    //  [X] it adds it to the middle
    // [X] duplicate bid id

    function test_insertAscendingPrice() external {
        _queue.initialize();

        _queue.insert(0, 1, 1);
        _queue.insert(1, 2, 1);
        _queue.insert(2, 3, 1);

        // Check values
        assertEq(_queue.getNumBids(), 3);

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 2);
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 3);

        maxId = _queue.getMaxId();
        assertEq(maxId, 1);
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 2);

        maxId = _queue.getMaxId();
        assertEq(maxId, 0);
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_singleBid() external {
        _queue.initialize();

        _queue.insert(0, 1, 1);

        // Check values
        assertEq(_queue.getNumBids(), 1);

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 0);
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_addLargerBid() external {
        _queue.initialize();

        _queue.insert(0, 1, 1);
        _queue.insert(1, 4, 2);

        // Check values
        assertEq(_queue.getNumBids(), 2);

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 1);
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 4);

        maxId = _queue.getMaxId();
        assertEq(maxId, 0);
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_addBidSamePrice() external {
        _queue.initialize();

        _queue.insert(1, 2, 1);
        _queue.insert(2, 4, 2);

        // Check values
        assertEq(_queue.getNumBids(), 2);

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 1);
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 2);

        maxId = _queue.getMaxId();
        assertEq(maxId, 2);
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 4);

        assertEq(_queue.isEmpty(), true);
    }

    function test_addBidSamePrice_reverse() external {
        _queue.initialize();

        _queue.insert(1, 4, 2);
        _queue.insert(2, 2, 1);

        // Check values
        assertEq(_queue.getNumBids(), 2);

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 1);
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 4);

        maxId = _queue.getMaxId();
        assertEq(maxId, 2);
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 2);

        assertEq(_queue.isEmpty(), true);
    }

    function test_addBidInMiddle() external {
        _queue.initialize();

        _queue.insert(0, 1, 1);
        _queue.insert(1, 3, 1);
        _queue.insert(2, 2, 1);

        // Check values
        assertEq(_queue.getNumBids(), 3);

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 1);
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 3);

        maxId = _queue.getMaxId();
        assertEq(maxId, 2);
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 2);

        maxId = _queue.getMaxId();
        assertEq(maxId, 0);
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_duplicateBidId() external {
        _queue.initialize();

        _queue.insert(0, 1, 1);
        _queue.insert(0, 3, 1);

        // Check values
        assertEq(_queue.getNumBids(), 2, "numBids mismatch");

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 0, "index 0: maxId mismatch");
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 3, "index 0: amountIn mismatch");

        // Unexpected behaviour when duplicate bid id is added
        maxId = _queue.getMaxId();
        assertEq(maxId, 0, "index 1: maxId mismatch");
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 0, "index 1: amountIn mismatch");

        assertEq(_queue.isEmpty(), true, "isEmpty mismatch");
    }

    function test_zeroAmountIn() external {
        _queue.initialize();

        _queue.insert(0, 0, 1);
        _queue.insert(1, 1, 1);

        // Check values
        assertEq(_queue.getNumBids(), 2, "numBids mismatch");

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 1, "index 0: maxId mismatch");
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 1, "index 0: amountIn mismatch");
        assertEq(maxBid.minAmountOut, 1, "index 0: minAmountOut mismatch");

        maxId = _queue.getMaxId();
        assertEq(maxId, 0, "index 1: maxId mismatch");
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 0, "index 1: amountIn mismatch");
        assertEq(maxBid.minAmountOut, 1, "index 1: minAmountOut mismatch");

        assertEq(_queue.isEmpty(), true, "isEmpty mismatch");
    }

    function test_zeroAmountOut_reverts() external {
        _queue.initialize();

        _queue.insert(1, 1, 1);

        vm.expectRevert();
        _queue.insert(0, 1, 0);
    }

    function test_largeNumber() external {
        _queue.initialize();

        _queue.insert(0, 1e18, 1e18);
        _queue.insert(1, 2e18, 1e18);

        // Check values
        assertEq(_queue.getNumBids(), 2, "numBids mismatch");

        // Check order of values
        uint64 maxId = _queue.getMaxId();
        assertEq(maxId, 1, "index 0: maxId mismatch");
        Bid memory maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 2e18, "index 0: amountIn mismatch");

        maxId = _queue.getMaxId();
        assertEq(maxId, 0, "index 1: maxId mismatch");
        maxBid = _queue.delMax();
        assertEq(maxBid.amountIn, 1e18, "index 1: amountIn mismatch");
    }
}
