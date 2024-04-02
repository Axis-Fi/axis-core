//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct Bid {
    uint64 id;
    uint96 amountIn;
    uint96 minAmountOut;
}

library BidEncoding {
    function encode(Bid memory self) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(self.id, self.amountIn, self.minAmountOut));
    }

    function decode(bytes32 data) internal pure returns (Bid memory) {
        uint64 bidId = uint64(uint256(data >> 192));
        uint96 amountIn = uint96(uint256(data >> 96));
        uint96 minAmountOut = uint96(uint256(data));
        return Bid(bidId, amountIn, minAmountOut);
    }
}

struct Queue {
    // bool flag; // need a non-dynamic field to avoid recursive type error, this is never used
    uint256 numBids;
    mapping(bytes32 => bytes32) prevBid;
    mapping(bytes32 => bytes32) nextBid;
}

/// @notice This library implements a max priority queue using an ordered array.
/// @dev    Insert operations are less efficient than a heap implementation, but
///         the queue is sorted after an insert and can be inspected in place.
///         Binary heap implementations only guarantee the top element is sorted.
library MaxPriorityQueue {
    using BidEncoding for Bid;
    using BidEncoding for bytes32;

    // represents the highest possibly priority bid in the queue
    bytes32 internal constant QUEUE_START =
        0x0000000000000000ffffffffffffffffffffffff000000000000000000000001;
    // represents the lowest possibly priority bid in the queue
    bytes32 internal constant QUEUE_END =
        0xffffffffffffffff000000000000000000000000000000000000000000000001;

    // ========== INITIALIZE ========== //

    function initialize(Queue storage self) internal {
        self.nextBid[QUEUE_START] = QUEUE_END;
        self.prevBid[QUEUE_END] = QUEUE_START;
    }
    
    // ========== HELPERS =========== //

    function contains(Queue storage self, bytes32 value)
        internal
        view
        returns (bool)
    {
        if (value == QUEUE_START) {
            return false;
        }
        // Note: QUEUE_END is not contained in the list since it has no
        // successor.
        return self.nextBid[value] != bytes32(0);
    }

    // ========== INSERTION ========== //

    function insert(
        Queue storage self,
        bytes32 prevHint_,
        uint64 bidId_,
        uint96 amountIn_,
        uint96 minAmountOut_
    ) internal {
        // Check that minAmountOut is not zero to avoid division by zero
        require(minAmountOut_ > 0, "invalid minAmountOut");

        // Encode the bid
        bytes32 key = Bid(bidId_, amountIn_, minAmountOut_).encode();

        // Verify that the bid is not already in the queue
        require(!contains(self, key), "bid already exists");

        // Confirm that the hint is higher priority than the new bid and has been in the queue at some point
        require(isHigherPriorityThan(prevHint_, key) && (prevHint_ == QUEUE_START || self.prevBid[prevHint_] != bytes32(0)), "invalid hint");

        // Use the hint as a starting point, find the exact spot to insert the new bid
        // Find the closest bid still in the queue with higher priority by traversing up the queue from the hint
        bytes32 anchor = prevHint_;
        while (!contains(self, anchor)) {
            anchor = self.prevBid[anchor];
        }
        
        // Now, traverse down the queue from the anchor to find the correct spot to insert the new bid
        bytes32 follower = self.nextBid[anchor];
        while (isHigherPriorityThan(follower, key)) {
            anchor = follower;
            follower = self.nextBid[anchor];
        }

        // Insert the new bid between the anchor and the follower
        self.nextBid[anchor] = key;
        self.prevBid[follower] = key;
        self.nextBid[key] = follower;
        self.prevBid[key] = anchor;

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
        bytes32 temp = self.nextBid[maxKey];
        delete self.nextBid[maxKey];
        delete self.prevBid[maxKey];
        self.nextBid[QUEUE_START] = temp;
        self.prevBid[temp] = QUEUE_START;

        // Decrement the number of bids in the queue
        self.numBids--;

        // Decode the max bid and return
        Bid memory maxBid = maxKey.decode();
        return (maxBid.id, maxBid.amountIn, maxBid.minAmountOut);
    }

    // ========== INSPECTION ========== //

    /// @notice Return the max bid from the queue without removing it.
    function getMax(Queue storage self) internal view returns (Bid memory) {
        return self.nextBid[QUEUE_START].decode();
    }

    /// @notice Return the number of bids in the queue.
    function getNumBids(Queue storage self) internal view returns (uint256) {
        return self.numBids;
    }

    // ========= UTILITIES ========= //

    function isHigherPriorityThan(
        bytes32 alpha,
        bytes32 beta
    ) private pure returns (bool) {
        Bid memory a = alpha.decode();
        Bid memory b = beta.decode();
        uint256 relA = uint256(a.amountIn) * uint256(b.minAmountOut);
        uint256 relB = uint256(b.amountIn) * uint256(a.minAmountOut);
        if (relA == relB) {
            return a.id < b.id;
        } else {
            return relA > relB;
        }
    }
}