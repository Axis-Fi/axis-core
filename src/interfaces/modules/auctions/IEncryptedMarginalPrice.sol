// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {Point} from "src/lib/ECIES.sol";

/// @notice Interface for encrypted marginal price (batch) auctions
/// @dev    This contract does not inherit from `BatchAuctionModule` in order to avoid conflicts. Implementing contracts should inherit from both `BatchAuctionModule` and this interface.
interface IEncryptedMarginalPrice {
    // ========== ERRORS ========== //

    error Auction_InvalidKey();
    error Auction_WrongState(uint96 lotId);
    error Bid_WrongState(uint96 lotId, uint64 bidId);
    error NotPermitted(address caller);

    // ========== EVENTS ========== //

    event BidDecrypted(
        uint96 indexed lotId, uint64 indexed bidId, uint96 amountIn, uint96 amountOut
    );

    // ========== DATA STRUCTURES ========== //

    /// @notice         Parameters that are used to set auction-specific data
    ///
    /// @param          minPrice            The minimum price (in quote tokens) that a bid must fulfill
    /// @param          minFillPercent      The minimum percentage of capacity that the lot must fill in order to settle. Maximum value = 100_000 = 1e5.
    /// @param          minBidSize          The minimum size of a bid in quote tokens
    /// @param          publicKey           The public key used to encrypt bids
    struct AuctionDataParams {
        uint256 minPrice;
        uint24 minFillPercent;
        uint256 minBidSize;
        Point publicKey;
    }

    /// @notice     Parameters to the bid function
    ///
    /// @param      encryptedAmountOut      The encrypted value of the bid amount out
    /// @param      bidPublicKey            The public key used to encrypt the bid
    struct BidParams {
        uint256 encryptedAmountOut;
        Point bidPublicKey;
    }

    /// @notice     The status of an auction lot
    enum LotStatus {
        Created,
        Decrypted,
        Settled
    }

    /// @notice        Struct containing auction-specific data
    ///
    /// @param         nextBidId           The ID of the next bid to be submitted
    /// @param         nextDecryptIndex    The index of the next bid to decrypt
    /// @param         status              The status of the auction
    /// @param         marginalBidId       The ID of the marginal bid (marking that bids following it are not filled)
    /// @param         marginalPrice       The marginal price of the auction (determined at settlement, blank before)
    /// @param         minFilled           The minimum amount of the lot that must be filled
    /// @param         minBidSize          The minimum size of a bid in quote tokens
    /// @param         publicKey           The public key used to encrypt bids (a point on the alt_bn128 curve from the generator point (1,2))
    /// @param         privateKey          The private key used to decrypt bids (not provided until after the auction ends)
    /// @param         bidIds              The list of bid IDs to decrypt in order of submission, excluding cancelled bids
    struct AuctionData {
        uint64 nextBidId; // 8 +
        uint64 nextDecryptIndex; // 8 +
        LotStatus status; // 1 +
        uint64 marginalBidId; // 8  = 25 - end of slot 1
        uint256 marginalPrice; // 32 - slot 2
        uint256 minPrice; // 32 - slot 3
        uint256 minFilled; // 32 - slot 4
        uint256 minBidSize; // 32 - slot 5
        Point publicKey; // 64 - slots 6 and 7
        uint256 privateKey; // 32 - slot 8
        uint64[] bidIds; // slots 9+
    }

    // ========== DECRYPTION ========== //

    /// @notice Submits the private key for the auction lot and decrypts an initial number of bids
    ///         It does not require gating. If the seller wishes to limit who can call, they can simply not reveal the key to anyone else.
    ///         On the other hand, if a key management service is used, then anyone can call it once the key is revealed.
    ///
    /// @param  lotId_      The lot ID of the auction to submit the private key for
    /// @param  privateKey_ The ECIES private key to decrypt the bids
    /// @param  num_        The number of bids to decrypt after submitting the private key (passed to `_decryptAndSortBids()`)
    /// @param  sortHints_  The sort hints for the bid decryption (passed to `_decryptAndSortBids()`)
    function submitPrivateKey(
        uint96 lotId_,
        uint256 privateKey_,
        uint64 num_,
        bytes32[] calldata sortHints_
    ) external;

    /// @notice Decrypts a batch of bids and sorts them by price in descending order
    ///
    /// @param  lotId_      The lot ID
    /// @param  num_        The number of bids to decrypt and sort
    /// @param  sortHints_  The sort hints for the bids
    function decryptAndSortBids(
        uint96 lotId_,
        uint64 num_,
        bytes32[] calldata sortHints_
    ) external;

    /// @notice     Returns the decrypted amountOut of a single bid without altering contract state
    ///
    /// @param      lotId_      The lot ID of the auction to decrypt the bid for
    /// @param      bidId_      The bid ID to decrypt
    /// @return     amountOut   The decrypted amount out
    function decryptBid(uint96 lotId_, uint64 bidId_) external view returns (uint256 amountOut);

    /// @notice     Returns the bid after `key_` in the queue
    ///
    /// @param      lotId_  The lot ID
    /// @param      key_    The key to search for
    /// @return     nextKey The key of the next bid in the queue
    function getNextInQueue(uint96 lotId_, bytes32 key_) external view returns (bytes32 nextKey);

    /// @notice     Returns the number of decrypted bids remaining in the queue
    ///
    /// @param      lotId_  The lot ID
    /// @return     numBids The number of decrypted bids remaining in the queue
    function getNumBidsInQueue(uint96 lotId_) external view returns (uint256 numBids);

    // ========== AUCTION INFORMATION ========== //

    /// @notice Returns the `AuctionData` data for an auction lot
    ///
    /// @param  lotId_          The lot ID
    /// @return auctionData_    The `AuctionData`
    function getAuctionData(uint96 lotId_)
        external
        view
        returns (AuctionData memory auctionData_);
}
