//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

struct Bid {
    uint96 queueId; // ID representing order of insertion
    uint96 bidId; // ID of encrypted bid to reference on settlement
    uint256 amountIn;
    uint256 minAmountOut;
}

/// @notice a max priority queue implementation, based off https://algs4.cs.princeton.edu/24pq/MaxPQ.java.html
/// @notice adapted from FrankieIsLost's min priority queue implementation at https://github.com/FrankieIsLost/smart-batched-auction/blob/master/contracts/libraries/MinPriorityQueue.sol
/// @author FrankieIsLost
/// @author Oighty (edits)
/// Bids in descending order
library MaxPriorityQueue {
    struct Queue {
        ///@notice incrementing bid id
        uint96 nextBidId;
        ///@notice array backing priority queue
        uint96[] queueIdList;
        ///@notice total number of bids in queue
        uint96 numBids;
        //@notice map bid ids to bids
        mapping(uint96 => Bid) queueIdToBidMap;
    }

    ///@notice initialize must be called before using queue.
    function initialize(Queue storage self) public {
        self.queueIdList.push(0);
        self.nextBidId = 1;
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
        uint96 maxId = self.queueIdList[1];
        return self.queueIdToBidMap[maxId];
    }

    ///@notice view bid by index in ascending order
    function getBid(Queue storage self, uint256 index) public view returns (Bid storage) {
        require(!isEmpty(self), "nothing to return");
        require(index <= self.numBids, "bid does not exist");
        require(index > 0, "cannot use 0 index");
        return self.queueIdToBidMap[self.queueIdList[index]];
    }

    ///@notice move bid up heap
    function _swim(Queue storage self, uint96 k) private {
        while (k > 1 && _isLess(self, k / 2, k)) {
            _exchange(self, k, k / 2);
            k = k / 2;
        }
    }

    ///@notice move bid down heap
    function _sink(Queue storage self, uint96 k) private {
        while (2 * k <= self.numBids) {
            uint96 j = 2 * k;
            if (j < self.numBids && _isLess(self, j, j + 1)) {
                j++;
            }
            if (!_isLess(self, k, j)) {
                break;
            }
            _exchange(self, k, j);
            k = j;
        }
    }

    ///@notice insert bid in heap
    function insert(
        Queue storage self,
        uint96 bidId,
        uint256 amountIn,
        uint256 minAmountOut
    ) public {
        _insert(self, Bid(self.nextBidId++, bidId, amountIn, minAmountOut));
    }

    ///@notice insert bid in heap
    function _insert(Queue storage self, Bid memory bid) private {
        self.queueIdList.push(bid.queueId);
        self.queueIdToBidMap[bid.queueId] = bid;
        self.numBids += 1;
        _swim(self, self.numBids);
    }

    ///@notice delete max bid from heap and return
    function delMax(Queue storage self) public returns (Bid memory) {
        require(!isEmpty(self), "nothing to delete");
        Bid memory max = self.queueIdToBidMap[self.queueIdList[1]];
        _exchange(self, 1, self.numBids--);
        self.queueIdList.pop();
        delete self.queueIdToBidMap[max.queueId];
        _sink(self, 1);
        return max;
    }

    ///@notice helper function to determine ordering. When two bids have the same price, give priority
    ///to the lower bid ID (inserted earlier)
    function _isLess(Queue storage self, uint256 i, uint256 j) private view returns (bool) {
        uint96 iId = self.queueIdList[i];
        uint96 jId = self.queueIdList[j];
        Bid memory bidI = self.queueIdToBidMap[iId];
        Bid memory bidJ = self.queueIdToBidMap[jId];
        uint256 relI = bidI.amountIn * bidJ.minAmountOut;
        uint256 relJ = bidJ.amountIn * bidI.minAmountOut;
        if (relI == relJ) {
            return bidI.bidId < bidJ.bidId;
        }
        return relI < relJ;
    }

    ///@notice helper function to exchange to bids in the heap
    function _exchange(Queue storage self, uint256 i, uint256 j) private {
        uint96 tempId = self.queueIdList[i];
        self.queueIdList[i] = self.queueIdList[j];
        self.queueIdList[j] = tempId;
    }
}
