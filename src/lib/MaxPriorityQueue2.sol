//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

struct Bid {
    uint96 amountIn;
    uint96 minAmountOut;
}

struct Queue {
    bool flag; // need a non-dynamic field to avoid recursive type error, this is never used
    uint64[] sortedIds;
    mapping(uint64 => Bid) bids;
}

/// @notice This library implements a max priority queue using an ordered array.
/// @dev    Insert operations are less efficient than a heap implementation, but
///         the queue is sorted after an insert and can be inspected in place.
///         Binary heap implementations only guarantee the top element is sorted.
library MaxPriorityQueue {
    // ========== INSERTION ========== //

    function insert(
        Queue storage self,
        uint64 bidId_,
        uint96 amountIn_,
        uint96 minAmountOut_
    ) internal {
        self.bids[bidId_] = Bid(amountIn_, minAmountOut_);
        uint256 n = self.sortedIds.length;
        self.sortedIds.push(bidId_);
        while (n > 0 && _isLessThan(self, n, n - 1)) {
            uint64 temp = self.sortedIds[n];
            self.sortedIds[n] = self.sortedIds[n - 1];
            self.sortedIds[n - 1] = temp;
            n--;
        }
    }

    // ========== REMOVAL ========== //

    /// @notice Remove the max bid from the queue and return it.
    function delMax(Queue storage self) internal returns (uint64, uint96, uint96) {
        uint64 maxId = self.sortedIds[self.sortedIds.length - 1];
        Bid memory maxBid = self.bids[maxId];
        delete self.bids[maxId];
        self.sortedIds.pop();
        return (maxId, maxBid.amountIn, maxBid.minAmountOut);
    }

    // ========== INSPECTION ========== //

    /// @notice Return the max bid from the queue without removing it.
    function getMax(Queue storage self) internal view returns (Bid memory) {
        uint64 maxId = self.sortedIds[self.sortedIds.length - 1];
        return self.bids[maxId];
    }

    /// @notice Return the number of bids in the queue.
    function getNumBids(Queue storage self) internal view returns (uint256) {
        return self.sortedIds.length;
    }

    /// @notice Return the bid at the given priority, zero indexed.
    function getBid(Queue storage self, uint64 priority) internal view returns (Bid storage) {
        uint64 maxIndex = uint64(self.sortedIds.length - 1);
        require(priority <= maxIndex, "bid does not exist");
        uint64 index = maxIndex - priority;
        uint64 bidId = self.sortedIds[index];
        return self.bids[bidId];
    }

    // ========= UTILITIES ========= //

    function _isLessThan(
        Queue storage self,
        uint256 alpha,
        uint256 beta
    ) private view returns (bool) {
        uint64 alphaId = self.sortedIds[alpha];
        uint64 betaId = self.sortedIds[beta];
        Bid memory a = self.bids[alphaId];
        Bid memory b = self.bids[betaId];
        uint256 relA = uint256(a.amountIn) * uint256(b.minAmountOut);
        uint256 relB = uint256(b.amountIn) * uint256(a.minAmountOut);
        if (relA == relB) {
            return alphaId > betaId;
        } else {
            return relA < relB;
        }
    }
}
