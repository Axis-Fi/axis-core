// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {MaxPriorityQueue, Queue, BidEncoding} from "../../src/lib/MaxPriorityQueue.sol";

contract MaxPriorityQueueTest is Test {
    using MaxPriorityQueue for Queue;

    Queue internal _queue;

    bytes32 internal constant _QUEUE_START =
        0x0000000000000000ffffffffffffffffffffffff000000000000000000000001;
    bytes32 internal constant _QUEUE_END =
        0xffffffffffffffff000000000000000000000000000000000000000000000001;

    uint256 internal constant _BASE_SCALE = 10;

    // [X] insert
    //     [X] sorts bids in the correct order
    //         [X] when added in ascending order
    //         [X] when added in descending order
    //         [X] when a single bid is added
    //         [X] when a larger bid is added
    //         [X] when a bid is added with the same price
    //             [X] the lower bidId is prioritized
    //         [X] when a bid is added in the middle
    //         [X] when a smaller bid is added
    //     [X] when a bid already exists
    //         [X] it reverts
    //     [X] when the hint doesn't exist
    //         [X] it reverts
    //     [X] when a bid is higher priority than its hint
    //         [X] it reverts
    //     [X] when a bid is the _QUEUE_START
    //         [X] it reverts
    //     [X] when minAmountOut is zero
    //         [X] it reverts
    // [X] delMax
    //     [X] when the queue is empty
    //         [X] it reverts
    //     [X] removes the highest priority bid and returns it
    // [X] getMax
    //     [X] returns the highest priority bid without removing it
    // [X] getNext
    //     [X] returns the bid following the one provided in the queue without removing it
    // [X] getNumBids
    //     [X] returns the number of bids in the queue
    //         [X] zero
    //         [X] one
    //         [X] many
    // [X] isEmpty
    //     [X] returns true when the queue is empty
    //     [X] returns false when the queue is not empty
    //         [X] one
    //         [X] many

    // ========== insert ========== //
    function test_insert_ascendingPrice() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 2, 3, 1, _BASE_SCALE);

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

    function test_insert_descendingPrice() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 2, 3, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);

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

    function test_insert_singleBid() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);

        // Check values
        assertEq(_queue.getNumBids(), 1);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 1);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_insert_addLargerBid() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 4, 2, _BASE_SCALE);

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

    function test_insert_addBidSamePrice() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        bytes32 prevHint = BidEncoding.encode(1, 2, 1);
        _queue.insert(prevHint, 2, 4, 2, _BASE_SCALE);

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

    function test_insert_addBidSamePrice_reverse() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 1, 4, 2, _BASE_SCALE);
        bytes32 prevHint = BidEncoding.encode(1, 4, 2);
        _queue.insert(prevHint, 2, 2, 1, _BASE_SCALE);

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

    function test_insert_addBidInMiddle() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 3, 1, _BASE_SCALE);
        bytes32 prevHint = BidEncoding.encode(1, 3, 1);
        _queue.insert(prevHint, 2, 2, 1, _BASE_SCALE);

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

    function test_insert_addSmallerBid() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);

        // Check values
        assertEq(_queue.getNumBids(), 2);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 2);
        assertEq(amountOut, 1);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 1);
        assertEq(amountOut, 1);

        assertEq(_queue.isEmpty(), true);
    }

    function test_insert_duplicateBidId() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 0, 3, 1, _BASE_SCALE);

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

    function test_insert_zeroAmountIn() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 0, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 1, 1, _BASE_SCALE);

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

    /// forge-config: default.allow_internal_expect_revert = true
    function test_insert_zeroAmountOut_reverts() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 1, 1, 1, _BASE_SCALE);

        bytes memory err = abi.encodePacked("invalid minAmountOut");
        vm.expectRevert(err);
        _queue.insert(_QUEUE_START, 0, 1, 0, _BASE_SCALE);
    }

    function test_insert_largeNumber() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1e18, 1e18, 1e18);
        _queue.insert(_QUEUE_START, 1, 2e18, 1e18, 1e18);

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

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevert_insert_bidAlreadyExists() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);

        bytes memory err = abi.encodePacked("bid already exists");
        vm.expectRevert(err);
        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevert_insert_prevHintDoesNotExist() external {
        _queue.initialize();

        bytes32 keyNotInQueue = BidEncoding.encode(1, 2, 1);
        assertFalse(_queue.contains(keyNotInQueue));

        bytes memory err = abi.encodePacked("prevKey not in queue");
        vm.expectRevert(err);
        _queue.insert(keyNotInQueue, 0, 1, 1, _BASE_SCALE);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevert_insert_bidHigherPriorityThanHint() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);

        bytes32 prevHint = BidEncoding.encode(1, 2, 1);
        bytes32 key = BidEncoding.encode(2, 3, 1);
        assertFalse(BidEncoding.isHigherPriorityThan(prevHint, key, _BASE_SCALE));

        bytes memory err = abi.encodePacked("invalid insert position");
        vm.expectRevert(err);
        _queue.insert(prevHint, 2, 3, 1, _BASE_SCALE);
    }

    function test_insert_precision_ordering() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 4e18 + 2, 2e18, 1e18);
        _queue.insert(_QUEUE_START, 1, 4e18 + 1, 2e18, 1e18);

        // Check values
        assertEq(_queue.getNumBids(), 2, "numBids mismatch");

        // Check order of values
        // Bid 1 will be marginally higher than bid 0
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 4e18 + 2);
        assertEq(amountOut, 2e18);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 4e18 + 1);
        assertEq(amountOut, 2e18);
    }

    function test_insert_precision() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 4e18 + 1, 2e18, 1e18);
        _queue.insert(_QUEUE_START, 1, 4e18 + 2, 2e18, 1e18);

        // Check values
        assertEq(_queue.getNumBids(), 2, "numBids mismatch");

        // Check order of values
        // Bid 1 price is marginally higher than bid 0, but that precision is lost, so it reverts to order of insertion
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 0);
        assertEq(amountIn, 4e18 + 1);
        assertEq(amountOut, 2e18);

        (bidId, amountIn, amountOut) = _queue.delMax();
        assertEq(bidId, 1);
        assertEq(amountIn, 4e18 + 2);
        assertEq(amountOut, 2e18);
    }

    // ========== delMax ========== //

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevert_delMax_emptyQueue() external {
        _queue.initialize();

        bytes memory err = abi.encodePacked("queue is empty");
        vm.expectRevert(err);
        _queue.delMax();
    }

    function test_delMax() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 2, 3, 1, _BASE_SCALE);

        // Check values
        assertEq(_queue.getNumBids(), 3);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.delMax();
        assertEq(bidId, 2);
        assertEq(amountIn, 3);
        assertEq(amountOut, 1);

        assertEq(_queue.getNumBids(), 2);
    }

    // ========== getMax ========== //

    function test_getMax() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 2, 3, 1, _BASE_SCALE);

        // Check values
        assertEq(_queue.getNumBids(), 3);

        // Check order of values
        (uint64 bidId, uint96 amountIn, uint96 amountOut) = _queue.getMax();
        assertEq(bidId, 2);
        assertEq(amountIn, 3);
        assertEq(amountOut, 1);

        assertEq(_queue.getNumBids(), 3);
    }

    // ========== getNext ========== //

    function test_getNext() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 2, 3, 1, _BASE_SCALE);

        // Check values
        assertEq(_queue.getNumBids(), 3);

        // Check order of values
        bytes32 firstKey = _queue.getNext(_QUEUE_START);
        assertEq(firstKey, BidEncoding.encode(2, 3, 1));

        bytes32 secondKey = _queue.getNext(firstKey);
        assertEq(secondKey, BidEncoding.encode(1, 2, 1));

        bytes32 thirdKey = _queue.getNext(secondKey);
        assertEq(thirdKey, BidEncoding.encode(0, 1, 1));

        assertEq(_queue.getNext(thirdKey), _QUEUE_END);

        assertEq(_queue.getNumBids(), 3);
    }

    // ========== getNumBids ========== //

    function test_getNumBids_zero() external {
        _queue.initialize();

        assertEq(_queue.getNumBids(), 0);
    }

    function test_getNumBids_one() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);

        assertEq(_queue.getNumBids(), 1);
    }

    function test_getNumBids_many() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 2, 3, 1, _BASE_SCALE);

        assertEq(_queue.getNumBids(), 3);
    }

    // ========== isEmpty ========== //

    function test_isEmpty_true() external {
        _queue.initialize();

        assert(_queue.isEmpty());
    }

    function test_isEmpty_false_one() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);

        assertFalse(_queue.isEmpty());
    }

    function test_isEmpty_false_many() external {
        _queue.initialize();

        _queue.insert(_QUEUE_START, 0, 1, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 1, 2, 1, _BASE_SCALE);
        _queue.insert(_QUEUE_START, 2, 3, 1, _BASE_SCALE);

        assertFalse(_queue.isEmpty());
    }
}
