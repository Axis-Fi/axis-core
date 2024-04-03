//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library BidEncoding {
    function encode(
        uint64 bidId,
        uint96 amountIn,
        uint96 minAmountOut
    ) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(bidId, amountIn, minAmountOut));
    }

    function decode(bytes32 data) internal pure returns (uint64, uint96, uint96) {
        uint64 bidId = uint64(uint256(data >> 192));
        uint96 amountIn = uint96(uint256(data >> 96));
        uint96 minAmountOut = uint96(uint256(data));
        return (bidId, amountIn, minAmountOut);
    }

    function isHigherPriorityThan(bytes32 alpha, bytes32 beta) internal pure returns (bool) {
        (uint64 aId, uint96 aAmountIn, uint96 aMinAmountOut) = decode(alpha);
        (uint64 bId, uint96 bAmountIn, uint96 bMinAmountOut) = decode(beta);
        uint256 relA = uint256(aAmountIn) * uint256(bMinAmountOut);
        uint256 relB = uint256(bAmountIn) * uint256(aMinAmountOut);
        if (relA == relB) {
            return aId < bId;
        } else {
            return relA > relB;
        }
    }
}

struct Queue {
    uint256 numBids;
    mapping(bytes32 => bytes32) nextBid;
}

/// @notice This library implements a max priority queue using a linked list.
/// We can achieve ~O(1) insertion by providing optimal hints for the insert position.
/// The linked list design automatically gives us O(1) removal of the max bid.
library MaxPriorityQueue {
    using BidEncoding for bytes32;

    // represents the highest possibly priority bid in the queue
    // Bid Id: 0, amountIn: 2^96 - 1, minAmountOut: 1 => price is 2^96 - 1 quote tokens per base token
    bytes32 internal constant QUEUE_START =
        0x0000000000000000ffffffffffffffffffffffff000000000000000000000001;
    // represents the lowest possibly priority bid in the queue
    // Bid Id: 2^64 - 1, amountIn: 0, minAmountOut: 1 => price is 0 quote tokens per base token
    bytes32 internal constant QUEUE_END =
        0xffffffffffffffff000000000000000000000000000000000000000000000001;

    // ========== INITIALIZE ========== //

    function initialize(Queue storage self) internal {
        self.nextBid[QUEUE_START] = QUEUE_END;
    }

    // ========== HELPERS =========== //

    function contains(Queue storage self, bytes32 value) internal view returns (bool) {
        // Note: QUEUE_START is considered in the queue since it is a valid previous key.
        // QUEUE_END is not contained in the list since it has no successor.
        return self.nextBid[value] != bytes32(0);
    }

    // ========== INSERTION ========== //

    function insert(
        Queue storage self,
        bytes32 prev_,
        uint64 bidId_,
        uint96 amountIn_,
        uint96 minAmountOut_
    ) internal {
        // Check that minAmountOut is not zero to avoid division by zero
        require(minAmountOut_ > 0, "invalid minAmountOut");

        // Encode the bid
        bytes32 key = BidEncoding.encode(bidId_, amountIn_, minAmountOut_);

        // TODO do we need to validate that the bid key is valid? our usage of the library should prevent this
        // It would cost extra gas to validate. This is a very sensitive function that will potentially be called 1,000s of times in a single auction.

        // Verify that the bid is not already in the queue
        require(!contains(self, key), "bid already exists");

        // Verify that the prev hint is in the queue
        require(contains(self, prev_), "prevKey not in queue");

        // Verify that the prev hint is higher priority than the new bid, otherwise revert
        require(prev_.isHigherPriorityThan(key), "invalid insert position");

        // Iterate through the queue to find the correct position to insert the new bid
        // Best performance is achieved when the bid should be submitted between prevHint and its next bid
        // However, we allow for suboptimal hints to be provided to make the function more flexible
        bytes32 next = self.nextBid[prev_];
        while (next.isHigherPriorityThan(key)) {
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
    function delMax(Queue storage self) internal returns (uint64, uint96, uint96) {
        // Get the max bid
        bytes32 maxKey = self.nextBid[QUEUE_START];
        require(maxKey != QUEUE_END, "queue is empty");

        // Remove the max bid from the queue
        self.nextBid[QUEUE_START] = self.nextBid[maxKey];
        delete self.nextBid[maxKey];

        // Decrement the number of bids in the queue
        self.numBids--;

        // Decode the max bid and return
        return maxKey.decode();
    }

    // ========== INSPECTION ========== //

    /// @notice Return the max bid from the queue without removing it.
    function getMax(Queue storage self) internal view returns (uint64, uint96, uint96) {
        return self.nextBid[QUEUE_START].decode();
    }

    /// @notice Return the key following the provided key
    function getNext(Queue storage self, bytes32 key) internal view returns (bytes32) {
        return self.nextBid[key];
    }

    /// @notice Return the number of bids in the queue.
    function getNumBids(Queue storage self) internal view returns (uint256) {
        return self.numBids;
    }
}
