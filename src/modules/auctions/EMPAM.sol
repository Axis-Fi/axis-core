/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

/// Protocol dependencies
import {AuctionModule, Auction} from "src/modules/Auction.sol";
import {Veecode, toVeecode} from "src/modules/Modules.sol";

// Libraries
import {ECIES, Point} from "src/lib/ECIES.sol";
import {MaxPriorityQueue, Queue, Bid as QueueBid} from "src/lib/MaxPriorityQueue.sol";

contract EncryptedMarginalPriceAuctionModule is AuctionModule {
    using MaxPriorityQueue for Queue;

    // ========== ERRORS ========== //


    // ========== EVENTS ========== //

    // ========== DATA STRUCTURES ========== //

    enum BidStatus {
        Submitted,
        Decrypted,
        Claimed // Bid status will also be set to claimed if the bid is cancelled/refunded
    }

    /// @notice        Core data for a bid
    ///
    /// @param         status              The status of the bid
    /// @param         bidder              The address of the bidder
    /// @param         recipient           The address of the recipient
    /// @param         amount              The amount of the bid
    /// @param         minAmountOut        The minimum amount out (not set until the bid is decrypted)
    /// @param         referrer            The address of the referrer
    struct Bid {
        BidStatus status; // 1 +
        address bidder; // 20 = 21 - end of slot 1
        address recipient; // 20 +
        uint96 amount; // 12 = 32 - end of slot 2
        uint96 minAmountOut; // 12 +
        address referrer; // 20 = 32 - end of slot 3
    }

    /// @notice        Struct containing data for an encrypted bid
    ///
    /// @param         encryptedAmountOut  The encrypted amount out, the bid amount is encrypted with a symmetric key that can be derived from the bidPubKey using the private key for the provided auction public key on the alt_bn128 curve
    /// @param         bidPubKey           The alt_bn128 public key used to encrypt the amount out (see bid() for more details)
    struct EncryptedBid {
        uint256 encryptedAmountOut;
        Point bidPubKey;
    }

    /// @notice        Struct containing auction-specific data
    ///
    /// @param         status              The status of the auction
    /// @param         nextBidId           The ID of the next bid to be submitted
    /// @param         nextDecryptIndex    The index of the next bid to decrypt
    /// @param         marginalPrice       The marginal price of the auction (determined at settlement, blank before)
    /// @param         publicKey           The public key used to encrypt bids (a point on the alt_bn128 curve from the generator point (1,2))
    /// @param         privateKey          The private key used to decrypt bids (not provided until after the auction ends)
    /// @param         bidIds              The list of bid IDs to decrypt in order of submission, excluding cancelled bids
    struct AuctionData {
        Auction.Status status; // 1 +
        uint64 nextBidId; // 8 +
        uint64 nextDecryptIndex; // 8 +
        uint96 marginalPrice; // 12 = 29 - end of slot 1
        uint96 minPrice;
        uint96 minFilled;
        uint96 minBidSize;
        Point publicKey; // 2 slots - end of slot 3
        uint256 privateKey; // 1 slot - end of slot 4
        uint64[] bidIds;
    }


    // ========== STATE VARIABLES ========== //

    /// @notice Constant for percentages
    /// @dev    1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint24 internal constant _MIN_BID_PERCENT = 10; // 0.01%

    /// @notice     Auction-specific data for a lot
    mapping(uint96 lotId => AuctionData) public auctionData;

    /// @notice General information about bids on a lot
    mapping(uint96 lotId => mapping(uint64 bidId => Bid)) public bids;

    /// @notice     Data for encryption information for a specific bid
    mapping(uint96 lotId => mapping(uint64 bidId => EncryptedBid)) public encryptedBids; // each encrypted amount is 5 slots (length + 4 slots) due to using 1024-bit RSA encryption

    /// @notice     Queue of decrypted bids for a lot (populated on decryption)
    mapping(uint96 lotId => Queue) public decryptedBids;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day initially
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01EMPAM");
    }

    function TYPE() public pure override returns (Type) {
        return Type.Auction;
    }

    // ========== MODIFIERS ========== //

    // ========== AUCTION ========== // 

    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override returns (bool prefundingRequired) {
        // Decode implementation params
        AuctionDataParams memory implParams = abi.decode(params_, (AuctionDataParams));

        // Validate params

        // minFillPercent must be less than or equal to 100%
        if (implParams.minFillPercent > _ONE_HUNDRED_PERCENT) revert Auction_InvalidParams();

        // minBidPercent must be greater than or equal to the global min and less than or equal to 100%
        if (
            implParams.minBidPercent < _MIN_BID_PERCENT
                || implParams.minBidPercent > _ONE_HUNDRED_PERCENT
        ) {
            revert Auction_InvalidParams();
        }

        // publicKey must be a valid point on the alt_bn128 curve with generator point (1, 2)
        if (!ECIES.isOnBn128(params_.publicKey)) revert InvalidParams();

        // Check that the public key is not the generator point (i.e. private key is zero) or the point at infinity
        if (
            (params_.publicKey.x == 1 && params_.publicKey.y == 2)
                || (params_.publicKey.x == 0 && params_.publicKey.y == 0)
        ) {
            revert InvalidParams();
        }

        AuctionData storage data = auctionData[lotId];
        data.publicKey = params_.publicKey;
        data.nextBidId = 1;
        decryptedBids[lotId].initialize();
    }

    // ========== BID ========== //
    

}
