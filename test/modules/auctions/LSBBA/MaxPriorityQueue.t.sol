// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Tests
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {MaxPriorityQueue, Bid as QueueBid} from "src/modules/auctions/LSBBA/MaxPriorityQueue.sol";

contract MaxPriorityQueueTest is Test {
    using MaxPriorityQueue for MaxPriorityQueue.Queue;

    MaxPriorityQueue.Queue queue;

    /// @notice    The initial index of the queue
    uint96 internal immutable _INITIAL_INDEX = 1;

    function setUp() public {
        MaxPriorityQueue.initialize(queue);
    }

    // Sorted by Bid.amountIn / Bid.minAmountOut

    // [X] initial values
    // [X] when a single bid is added
    // [X] when a larger bid is added
    //  [X] it sorts in ascending order
    // [X] when a bid is added in the middle
    //  [X] it adds it to the middle

    function test_initialize() public {
        assertEq(queue.nextBidId, 1);
        assertEq(queue.queueIdList.length, 1);
        assertEq(queue.queueIdList[0], 0);
        assertEq(queue.numBids, 0);

        // empty
        assertTrue(queue.isEmpty());
    }

    function test_singleBid() public {
        queue.insert(0, 1, 1); // Price = 1/1

        // get bid
        QueueBid memory bid = queue.getBid(_INITIAL_INDEX);
        assertEq(bid.queueId, 1, "1: queueId mismatch");
        assertEq(bid.bidId, 0);
        assertEq(bid.amountIn, 1);
        assertEq(bid.minAmountOut, 1);

        // get max bid
        bid = queue.getMax();
        assertEq(bid.queueId, 1);
        assertEq(bid.bidId, 0);
        assertEq(bid.amountIn, 1);
        assertEq(bid.minAmountOut, 1);

        // numBids incremented
        assertEq(queue.numBids, 1);

        // not empty
        assertFalse(queue.isEmpty());

        // queueIdList
        assertEq(queue.queueIdList.length, 2);
        assertEq(queue.queueIdList[0], 0);
        assertEq(queue.queueIdList[1], 1);
    }

    function test_addLargerBid() public {
        // Add the first bid
        queue.insert(0, 1, 1); // Price = 1/1

        // Add a second bid that is larger
        queue.insert(1, 4, 2); // Price = 4/2 = 2

        // get first sorted bid (bid id = 1)
        QueueBid memory bid = queue.getBid(_INITIAL_INDEX);
        assertEq(bid.queueId, 2, "1: queueId mismatch");
        assertEq(bid.bidId, 1, "1: bidId mismatch");
        assertEq(bid.amountIn, 4, "1: amountIn mismatch");
        assertEq(bid.minAmountOut, 2, "1: minAmountOut mismatch");

        // get second sorted bid (bid id = 0)
        bid = queue.getBid(_INITIAL_INDEX + 1);
        assertEq(bid.queueId, 1, "2: queueId mismatch");
        assertEq(bid.bidId, 0, "2: bidId mismatch");
        assertEq(bid.amountIn, 1, "2: amountIn mismatch");
        assertEq(bid.minAmountOut, 1, "2: minAmountOut mismatch");

        // get max bid (bid id = 0)
        bid = queue.getMax();
        assertEq(bid.queueId, 1, "min: queueId mismatch");
        assertEq(bid.bidId, 0);
        assertEq(bid.amountIn, 1);
        assertEq(bid.minAmountOut, 1);

        // numBids incremented
        assertEq(queue.numBids, 2);

        // not empty
        assertFalse(queue.isEmpty());

        // queueIdList
        assertEq(queue.queueIdList.length, 3);
        assertEq(queue.queueIdList[0], 0);
        assertEq(queue.queueIdList[1], 2);
        assertEq(queue.queueIdList[2], 1);
    }

    function test_addSmallerBid() public {
        // Add the first bid
        queue.insert(0, 1, 1); // queueId = 1, price = 1/1

        // Add a second bid that is larger
        queue.insert(1, 4, 2); // queueId = 2, price = 4/2 = 2

        // Add a third bid that is smaller than the second bid
        queue.insert(2, 3, 2); // queueId = 3, price = 3/2 = 1.5

        // get first sorted bid (bid id = 1)
        console2.log("getBid(1)");
        QueueBid memory bid = queue.getBid(_INITIAL_INDEX);
        assertEq(bid.queueId, 2, "index 1: queueId mismatch");
        assertEq(bid.bidId, 1, "index 1: bidId mismatch");
        assertEq(bid.amountIn, 4, "index 1: amountIn mismatch");
        assertEq(bid.minAmountOut, 2, "index 1: minAmountOut mismatch");

        // get second sorted bid (bid id = 2)
        console2.log("getBid(2)");
        bid = queue.getBid(_INITIAL_INDEX + 1);
        assertEq(bid.queueId, 3, "index 2: queueId mismatch");
        assertEq(bid.bidId, 2, "index 2: bidId mismatch");
        assertEq(bid.amountIn, 3, "index 2: amountIn mismatch");
        assertEq(bid.minAmountOut, 2, "index 2: minAmountOut mismatch");

        // get third sorted bid (bid id = 0)
        console2.log("getBid(3)");
        bid = queue.getBid(_INITIAL_INDEX + 2);
        assertEq(bid.queueId, 1, "index 3: queueId mismatch");
        assertEq(bid.bidId, 0, "index 3: bidId mismatch");
        assertEq(bid.amountIn, 1, "index 3: amountIn mismatch");
        assertEq(bid.minAmountOut, 1, "index 3: minAmountOut mismatch");

        // get max bid (bid id = 0)
        console2.log("getMax()");
        bid = queue.getMax();
        assertEq(bid.queueId, 1);
        assertEq(bid.bidId, 0);
        assertEq(bid.amountIn, 1);
        assertEq(bid.minAmountOut, 1);

        // numBids incremented
        assertEq(queue.numBids, 3);

        // not empty
        assertFalse(queue.isEmpty());

        // queueIdList
        console2.log("queueIdList");
        assertEq(queue.queueIdList.length, 4);
        assertEq(queue.queueIdList[0], 0);
        assertEq(queue.queueIdList[1], 2);
        assertEq(queue.queueIdList[2], 3);
        assertEq(queue.queueIdList[3], 1);
    }

    function test_fourItems() public {
        // Add the first bid
        queue.insert(0, 1, 1); // queueId = 1, price = 1/1

        // Add a second bid that is larger
        queue.insert(1, 4, 2); // queueId = 2, price = 4/2 = 2

        // Add a third bid that is smaller than the second bid
        queue.insert(2, 3, 2); // queueId = 3, price = 3/2 = 1.5

        // Add a fourth bid that is smaller than the first bid
        queue.insert(3, 1, 2); // queueId = 4, price = 1/2

        // get first sorted bid (bid id = 1)
        console2.log("getBid(1)");
        QueueBid memory bid = queue.getBid(_INITIAL_INDEX);
        assertEq(bid.queueId, 2, "index 1: queueId mismatch");
        assertEq(bid.bidId, 1, "index 1: bidId mismatch");
        assertEq(bid.amountIn, 4, "index 1: amountIn mismatch");
        assertEq(bid.minAmountOut, 2, "index 1: minAmountOut mismatch");

        // get second sorted bid (bid id = 2)
        console2.log("getBid(2)");
        bid = queue.getBid(_INITIAL_INDEX + 1);
        assertEq(bid.queueId, 3, "index 2: queueId mismatch");
        assertEq(bid.bidId, 2, "index 2: bidId mismatch");
        assertEq(bid.amountIn, 3, "index 2: amountIn mismatch");
        assertEq(bid.minAmountOut, 2, "index 2: minAmountOut mismatch");

        // get third sorted bid (bid id = 0)
        console2.log("getBid(3)");
        bid = queue.getBid(_INITIAL_INDEX + 2);
        assertEq(bid.queueId, 1, "index 3: queueId mismatch");
        assertEq(bid.bidId, 0, "index 3: bidId mismatch");
        assertEq(bid.amountIn, 1, "index 3: amountIn mismatch");
        assertEq(bid.minAmountOut, 1, "index 3: minAmountOut mismatch");

        // get fourth sorted bid (bid id = 3)
        console2.log("getBid(4)");
        bid = queue.getBid(_INITIAL_INDEX + 3);
        assertEq(bid.queueId, 4, "index 4: queueId mismatch");
        assertEq(bid.bidId, 3, "index 4: bidId mismatch");
        assertEq(bid.amountIn, 1, "index 4: amountIn mismatch");
        assertEq(bid.minAmountOut, 2, "index 4: minAmountOut mismatch");

        // get max bid (bid id = 3)
        console2.log("getMax()");
        bid = queue.getMax();
        assertEq(bid.queueId, 4);
        assertEq(bid.bidId, 3);
        assertEq(bid.amountIn, 1);
        assertEq(bid.minAmountOut, 2);

        // numBids incremented
        assertEq(queue.numBids, 3);

        // not empty
        assertFalse(queue.isEmpty());

        // queueIdList
        console2.log("queueIdList");
        assertEq(queue.queueIdList.length, 4);
        assertEq(queue.queueIdList[0], 0);
        assertEq(queue.queueIdList[1], 2);
        assertEq(queue.queueIdList[2], 3);
        assertEq(queue.queueIdList[3], 1);
        assertEq(queue.queueIdList[4], 4);
    }
}
