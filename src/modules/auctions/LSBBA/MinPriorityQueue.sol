//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

struct Bid {
    uint96 bidId; // ID in queue
    uint96 encId; // ID of encrypted bid to reference on settlement
    uint256 amountIn;
    uint256 minAmountOut;
}

/// @notice a min priority queue implementation, based off https://algs4.cs.princeton.edu/24pq/MinPQ.java.html
/// @notice adapted from FrankieIsLost's implementation at https://github.com/FrankieIsLost/smart-batched-auction/blob/master/contracts/libraries/MinPriorityQueue.sol
/// @author FrankieIsLost
/// @author Oighty (edits)
library MinPriorityQueue {
    struct Queue {
        ///@notice incrementing bid id
        uint96 nextBidId;
        ///@notice array backing priority queue
        uint96[] bidIdList;
        ///@notice total number of bids in queue
        uint96 numBids;
        //@notice map bid ids to bids
        mapping(uint96 => Bid) bidIdToBidMap;
    }

    ///@notice initialize must be called before using queue.
    function initialize(Queue storage self) public {
        self.bidIdList.push(0);
        self.nextBidId = 1;
    }

    function isEmpty(Queue storage self) public view returns (bool) {
        return self.numBids == 0;
    }

    function getNumBids(Queue storage self) public view returns (uint256) {
        return self.numBids;
    }

    ///@notice view min bid
    function getMin(Queue storage self) public view returns (Bid storage) {
        require(!isEmpty(self), "nothing to return");
        uint96 minId = self.bidIdList[1];
        return self.bidIdToBidMap[minId];
    }

    ///@notice view bid by index
    function getBid(Queue storage self, uint256 index) public view returns (Bid storage) {
        require(!isEmpty(self), "nothing to return");
        require(index <= self.numBids, "bid does not exist");
        require(index > 0, "cannot use 0 index");
        return self.bidIdToBidMap[self.bidIdList[index]];
    }

    ///@notice move bid up heap
    function swim(Queue storage self, uint96 k) private {
        while (k > 1 && isGreater(self, k / 2, k)) {
            exchange(self, k, k / 2);
            k = k / 2;
        }
    }

    ///@notice move bid down heap
    function sink(Queue storage self, uint96 k) private {
        while (2 * k <= self.numBids) {
            uint96 j = 2 * k;
            if (j < self.numBids && isGreater(self, j, j + 1)) {
                j++;
            }
            if (!isGreater(self, k, j)) {
                break;
            }
            exchange(self, k, j);
            k = j;
        }
    }

    ///@notice insert bid in heap
    function insert(
        Queue storage self,
        uint96 encId,
        uint256 amountIn,
        uint256 minAmountOut
    ) public {
        insert(self, Bid(self.nextBidId++, encId, amountIn, minAmountOut));
    }

    ///@notice insert bid in heap
    function insert(Queue storage self, Bid memory bid) private {
        self.bidIdList.push(bid.bidId);
        self.bidIdToBidMap[bid.bidId] = bid;
        self.numBids += 1;
        swim(self, self.numBids);
    }

    ///@notice delete min bid from heap and return
    function delMin(Queue storage self) public returns (Bid memory) {
        require(!isEmpty(self), "nothing to delete");
        Bid memory min = self.bidIdToBidMap[self.bidIdList[1]];
        exchange(self, 1, self.numBids--);
        self.bidIdList.pop();
        delete self.bidIdToBidMap[min.bidId];
        sink(self, 1);
        return min;
    }

    ///@notice helper function to determine ordering. When two bids have the same price, give priority
    ///to the lower bid ID (inserted earlier)
    function isGreater(Queue storage self, uint256 i, uint256 j) private view returns (bool) {
        uint96 iId = self.bidIdList[i];
        uint96 jId = self.bidIdList[j];
        Bid memory bidI = self.bidIdToBidMap[iId];
        Bid memory bidJ = self.bidIdToBidMap[jId];
        uint256 relI = bidI.amountIn * bidJ.minAmountOut;
        uint256 relJ = bidJ.amountIn * bidI.minAmountOut;
        if (relI == relJ) {
            return iId > jId;
        }
        return relI < relJ;
    }

    ///@notice helper function to exchange to bids in the heap
    function exchange(Queue storage self, uint256 i, uint256 j) private {
        uint96 tempId = self.bidIdList[i];
        self.bidIdList[i] = self.bidIdList[j];
        self.bidIdList[j] = tempId;
    }
}
