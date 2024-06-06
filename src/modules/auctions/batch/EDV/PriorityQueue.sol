// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

library BidEncoding {
    function encode(uint64 bidId, uint128 value) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(bidId, value));
    }

    function decode(bytes32 data) internal pure returns (uint64, uint128) {
        uint64 bidId = uint64(uint256(data >> 192));
        uint128 value = uint128(uint256(data >> 64));
        return (bidId, value);
    }

    function isHigherPriorityThan(
        bytes32 alpha,
        bytes32 beta,
        bool isMaxPriorityQueue
    ) internal pure returns (bool) {
        (uint64 aId, uint128 aValue) = decode(alpha);
        (uint64 bId, uint128 bValue) = decode(beta);
        if (aValue == bValue) {
            return aId < bId;
        } else {
            return isMaxPriorityQueue ? aValue > bValue : aValue < bValue;
        }
    }
}

struct Queue {
    /// @notice     The type of priority queue (false = min, true = max)
    bool isMaxPriorityQueue;
    /// @notice     The number of bids in the queue
    uint256 numBids;
    /// @notice     Mapping of bid keys to the next bid key in the queue
    mapping(bytes32 => bytes32) nextBid;
}

/// @notice     This library implements a priority queue using a linked list specific to the EDV auction.
///             It can be configured as a min priority queue or a max priority queue on creation.
///             We can achieve ~O(1) insertion by providing optimal hints for the insert position.
///             The linked list design automatically gives us O(1) removal of the max bid.
library PriorityQueue {
    using BidEncoding for bytes32;

    /* solhint-disable private-vars-leading-underscore */
    // represents the highest possibly priority bid in a min priority queue
    // Bid Id: 0, Value: 0
    bytes32 internal constant MIN_QUEUE_START =
        0x0000000000000000000000000000000000000000000000000000000000000000;
    // represents the lowest possibly priority bid in a min priority queue
    // Bid Id: 2^64 - 1, Value: 2^128 - 1
    bytes32 internal constant MIN_QUEUE_END =
        0xffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000;

    // represents the highest possibly priority bid in a max priority queue
    // Bid Id: 0, Value: 2^128 - 1
    bytes32 internal constant MAX_QUEUE_START =
        0x0000000000000000ffffffffffffffffffffffffffffffff0000000000000000;
    // represents the lowest possibly priority bid in a max priority queue
    // Bid Id: 2^64 - 1, Value: 0
    bytes32 internal constant MAX_QUEUE_END =
        0xffffffffffffffff000000000000000000000000000000000000000000000000;
    /* solhint-enable private-vars-leading-underscore */

    // ========== INITIALIZE ========== //

    function initialize(Queue storage self, bool isMaxPriorityQueue) internal {
        self.isMaxPriorityQueue = isMaxPriorityQueue;
        if (isMaxPriorityQueue) {
            self.nextBid[MAX_QUEUE_START] = MAX_QUEUE_END;
        } else {
            self.nextBid[MIN_QUEUE_START] = MIN_QUEUE_END;
        }
    }

    // ========== HELPERS =========== //

    function contains(Queue storage self, bytes32 value) internal view returns (bool) {
        // Note: QUEUE_START is considered in the queue since it is a valid previous key.
        // QUEUE_END is not contained in the list since it has no successor.
        return self.nextBid[value] != bytes32(0);
    }

    // ========== INSERTION ========== //

    function insert(Queue storage self, bytes32 prev_, uint64 bidId_, uint128 value_) internal {
        // Encode the bid
        bytes32 key = BidEncoding.encode(bidId_, value_);

        // Verify that the bid is not already in the queue
        require(!contains(self, key), "bid already exists");

        // Verify that the prev hint is in the queue
        require(contains(self, prev_), "prevKey not in queue");

        // Verify that the prev hint is higher priority than the new bid, otherwise revert
        require(prev_.isHigherPriorityThan(key, self.isMaxPriorityQueue), "invalid insert position");

        // Iterate through the queue to find the correct position to insert the new bid
        // Best performance is achieved when the bid should be submitted between prevHint and its next bid
        // However, we allow for suboptimal hints to be provided to make the function more flexible
        bytes32 next = self.nextBid[prev_];
        while (next.isHigherPriorityThan(key, self.isMaxPriorityQueue)) {
            prev_ = next;
            next = self.nextBid[next];
        }

        // Insert the new bid between the previous bid and the previous next bid
        self.nextBid[prev_] = key;
        self.nextBid[key] = next;

        // Increment the number of bids in the queue
        self.numBids++;
    }

    // ========== REMOVAL ========== //

    /// @notice Remove the max bid from the queue and return it.
    function delMax(Queue storage self) internal returns (uint64, uint128) {
        (bytes32 queueStart, bytes32 queueEnd) = self.isMaxPriorityQueue
            ? (MAX_QUEUE_START, MAX_QUEUE_END)
            : (MIN_QUEUE_START, MIN_QUEUE_END);

        // Get the max bid
        bytes32 maxKey = self.nextBid[queueStart];
        require(maxKey != queueEnd, "queue is empty");

        // Remove the max bid from the queue
        self.nextBid[queueStart] = self.nextBid[maxKey];
        delete self.nextBid[maxKey];

        // Decrement the number of bids in the queue
        self.numBids--;

        // Decode the max bid and return
        return maxKey.decode();
    }

    // ========== INSPECTION ========== //

    /// @notice Return the max bid from the queue without removing it.
    function getMax(Queue storage self) internal view returns (uint64, uint128) {
        bytes32 queueStart = self.isMaxPriorityQueue ? MAX_QUEUE_START : MIN_QUEUE_START;
        return self.nextBid[queueStart].decode();
    }

    /// @notice Return the key following the provided key
    function getNext(Queue storage self, bytes32 key) internal view returns (bytes32) {
        return self.nextBid[key];
    }

    /// @notice Return the number of bids in the queue.
    function getNumBids(Queue storage self) internal view returns (uint256) {
        return self.numBids;
    }

    /// @notice Return true if the queue is empty.
    function isEmpty(Queue storage self) internal view returns (bool) {
        return self.numBids == 0;
    }
}
