//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

struct Bid {
    uint96 amountIn;
    uint96 minAmountOut;
}

struct Queue {
    ///@notice array backing priority queue
    uint64[] bidIdList;
    ///@notice total number of bids in queue
    uint64 numBids;
    //@notice map bid ids to bids
    mapping(uint64 => Bid) idToBidMap;
}

/// @notice a max priority queue implementation on a binary heap, based off https://algs4.cs.princeton.edu/24pq/MaxPQ.java.html
/// @notice adapted from FrankieIsLost's min priority queue implementation at https://github.com/FrankieIsLost/smart-batched-auction/blob/master/contracts/libraries/MinPriorityQueue.sol
/// @author FrankieIsLost
/// @author Oighty (edits)
/// Bids in descending order
library MaxPriorityQueue {


    ///@notice initialize must be called before using queue.
    function initialize(Queue storage self) public {
        self.bidIdList.push(0);
    }

    function isEmpty(Queue storage self) public view returns (bool) {
        return self.numBids == 0;
    }

    function getNumBids(Queue storage self) public view returns (uint256) {
        return self.numBids;
    }

    ///@notice view max bid
    function getMax(Queue storage self) public view returns (Bid storage) {
        require(!isEmpty(self), "nothing to return");
        uint64 maxId = self.bidIdList[1];
        return self.idToBidMap[maxId];
    }

    function getMaxId(Queue storage self) public view returns (uint64) {
        require(!isEmpty(self), "nothing to return");
        return self.bidIdList[1];
    }

    ///@notice move bid up heap
    function swim(Queue storage self, uint64 k) private {
        while (k > 1 && isLess(self, k / 2, k)) {
            exchange(self, k, k / 2);
            k = k / 2;
        }
    }

    ///@notice move bid down heap
    function sink(Queue storage self, uint64 k) private {
        while (2 * k <= self.numBids) {
            uint64 j = 2 * k;
            if (j < self.numBids && isLess(self, j, j + 1)) {
                j++;
            }
            if (!isLess(self, k, j)) {
                break;
            }
            exchange(self, k, j);
            k = j;
        }
    }

    ///@notice insert bid in heap
    function insert(
        Queue storage self,
        uint64 bidId,
        uint96 amountIn,
        uint96 minAmountOut
    ) public {
        insert(self, bidId, Bid(amountIn, minAmountOut));
    }

    ///@notice insert bid in heap
    function insert(Queue storage self, uint64 bidId, Bid memory bid) private {
        self.bidIdList.push(bidId);
        self.idToBidMap[bidId] = bid;
        self.numBids += 1;
        swim(self, self.numBids);
    }

    ///@notice delete max bid from heap and return
    function delMax(Queue storage self) public returns (Bid memory) {
        require(!isEmpty(self), "nothing to delete");
        uint64 bidId = self.bidIdList[1];
        Bid memory max = self.idToBidMap[bidId];
        exchange(self, 1, self.numBids--);
        self.bidIdList.pop();
        delete self.idToBidMap[bidId];
        sink(self, 1);
        return max;
    }

    ///@notice helper function to determine ordering. When two bids have the same price, give priority
    ///to the lower bid ID (inserted earlier)
    function isLess(Queue storage self, uint256 i, uint256 j) private view returns (bool) {
        uint64 iId = self.bidIdList[i];
        uint64 jId = self.bidIdList[j];
        Bid memory bidI = self.idToBidMap[iId];
        Bid memory bidJ = self.idToBidMap[jId];
        uint256 relI = bidI.amountIn * bidJ.minAmountOut;
        uint256 relJ = bidJ.amountIn * bidI.minAmountOut;
        if (relI == relJ) {
            return iId < jId;
        }
        return relI < relJ;
    }

    ///@notice helper function to exchange to bids in the heap
    function exchange(Queue storage self, uint256 i, uint256 j) private {
        uint64 tempId = self.bidIdList[i];
        self.bidIdList[i] = self.bidIdList[j];
        self.bidIdList[j] = tempId;
    }
}