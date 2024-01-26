//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

struct Bid {
    uint96 bidId; // ID of encrypted bid to reference on settlement
    uint256 amountIn;
    uint256 minAmountOut;
}

struct Queue {
    bool flag; // need a non-dynamic field to avoid recursive type error, this is never used
    uint96[] sortedIds;
    mapping(uint96 => Bid) bids;
}

/// @notice This library implements a max priority queue using an ordered array.
/// @dev    Insert operations are less efficient than a heap implementation, but
///         the queue is sorted after an insert and can be inspected in place.
///         Binary heap implementations only guarantee the top element is sorted.
library MaxPriorityQueue {
    // ========== INSERTION ========== //

    function insert(
        Queue storage self,
        uint96 bidId_,
        uint256 amountIn_,
        uint256 minAmountOut_
    ) public {
        Bid memory bid = Bid(bidId_, amountIn_, minAmountOut_);
        self.bids[bidId_] = bid;
        uint256 n = self.sortedIds.length;
        self.sortedIds.push(bidId_);
        while (n > 0 && isLessThan(self, n, n - 1)) {
            uint96 temp = self.sortedIds[n];
            self.sortedIds[n] = self.sortedIds[n - 1];
            self.sortedIds[n - 1] = temp;
            n--;
        }
    }

    // ========== REMOVAL ========== //

    /// @notice Remove the max bid from the queue and return it.
    function popMax(Queue storage self) public returns (Bid memory) {
        uint96 maxId = self.sortedIds[self.sortedIds.length - 1];
        Bid memory maxBid = self.bids[maxId];
        delete self.bids[maxId];
        self.sortedIds.pop();
        return maxBid;
    }

    // ========== INSPECTION ========== //

    /// @notice Return the max bid from the queue without removing it.
    function getMax(Queue storage self) public view returns (Bid memory) {
        uint96 maxId = self.sortedIds[self.sortedIds.length - 1];
        return self.bids[maxId];
    }

    /// @notice Return the number of bids in the queue.
    function getNumBids(Queue storage self) public view returns (uint256) {
        return self.sortedIds.length;
    }

    /// @notice Return the bid at the given priority, zero indexed.
    function getBid(Queue storage self, uint96 priority) public view returns (Bid storage) {
        uint96 maxIndex = uint96(self.sortedIds.length - 1);
        require(priority <= maxIndex, "bid does not exist");
        uint96 index = maxIndex - priority;
        uint96 bidId = self.sortedIds[index];
        return self.bids[bidId];
    }

    // ========= UTILITIES ========= //

    function isLessThan(
        Queue storage self,
        uint256 alpha,
        uint256 beta
    ) private view returns (bool) {
        uint96 alphaId = self.sortedIds[alpha];
        uint96 betaId = self.sortedIds[beta];
        Bid memory a = self.bids[alphaId];
        Bid memory b = self.bids[betaId];
        uint256 relA = a.amountIn * b.minAmountOut;
        uint256 relB = b.amountIn * a.minAmountOut;
        if (relA == relB) {
            return alphaId < betaId;
        } else {
            return relA < relB;
        }
    }
}
