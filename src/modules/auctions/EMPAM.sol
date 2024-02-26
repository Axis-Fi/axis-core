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
    error Auction_AmountLessThanMinimum();
    error Auction_InvalidKey();
    error Auction_WrongState();


    // ========== EVENTS ========== //
    event BidDecrypted(
        uint96 indexed lotId, uint64 indexed bidId, uint96 amountIn, uint96 amountOut
    );

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
    /// @param         amount              The amount of the bid
    /// @param         minAmountOut        The minimum amount out (not set until the bid is decrypted)
    /// @param         referrer            The address of the referrer
    struct Bid {
        address bidder; // 20 +
        uint96 amount; // 12 = 32 - end of slot 1
        uint96 minAmountOut; // 12 +
        address referrer; // 20 = 32 - end of slot 2
        BidStatus status; // 1 - slot 3
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
        uint64 nextBidId; // 8 +
        uint96 marginalPrice; // 12 +
        uint96 minPrice; // 12 = 32 - end of slot 1
        uint64 nextDecryptIndex; // 8 +
        uint96 minFilled; // 12 +
        uint96 minBidSize; // 12 = 32 - end of slot 2
        Auction.Status status; // 1 - slot 3
        Point publicKey; // 64 - slots 4 and 5
        uint256 privateKey; // 32 - slot 6
        uint64[] bidIds; // slots 7+
    }

    struct AuctionDataParams {
        uint96 minPrice;
        uint24 minFillPercent;
        uint24 minBidPercent;
        Point publicKey;
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

        // minPrice must not be zero
        if (implParams.minPrice == 0) revert Auction_InvalidParams();

        // minFillPercent must be less than or equal to 100%
        if (implParams.minFillPercent > _ONE_HUNDRED_PERCENT) revert Auction_InvalidParams();

        // minBidPercent must be greater than or equal to the global min and less than or equal to 100%
        if (
            implParams.minBidPercent < _MIN_BID_PERCENT
                || implParams.minBidPercent > _ONE_HUNDRED_PERCENT
        ) {
            revert Auction_InvalidParams();
        }

        // publicKey must be a valid point for the encryption library
        if (!ECIES.isValid(implParams.publicKey)) revert Auction_InvalidParams();

        // Set auction data
        AuctionData storage data = auctionData[lotId_];
        data.minPrice = implParams.minPrice;
        // These calculations won't overflow if capacity doesn't overflow uint96 because the minFillPercent and minBidPercent are both less than or equal to 100%
        data.minFilled = uint96((uint256(lot_.capacity) * implParams.minFillPercent) / _ONE_HUNDRED_PERCENT);
        data.minBidSize = uint96((uint256(lot_.capacity) * implParams.minBidPercent) / _ONE_HUNDRED_PERCENT);
        data.publicKey = implParams.publicKey;
        data.nextBidId = 1;

        decryptedBids[lotId_].initialize();

        // This auction type requires pre-funding
        // This setting requires the capacity to be in the base token,
        // so we know the capacity values above are in base token units.
        prefundingRequired = true;
    }

    function _cancelAuction(uint96 lotId_) internal override {
        // Validation
        // Batch auctions cannot be cancelled once started, otherwise the seller could cancel the auction after bids have been submitted
        _revertIfLotActive(lotId_);

        // Auction cannot be cancelled once it has concluded
        _revertIfLotConcluded(lotId_);

        // Set auction status to settled so that bids can be refunded
        auctionData[lotId_].status = Auction.Status.Settled;
    }

    // ========== BID ========== //

    /// @inheritdoc AuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Stores the encrypted bid
    ///             - Adds the bid ID to the list of bids to decrypt (in `AuctionData.bidIds`)
    ///             - Returns the bid ID
    ///
    ///             This function reverts if:
    ///             - The amount is less than the minimum bid size for the lot
    function _bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint96 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint64 bidId) {
        // Decode auction data
        (uint256 encryptedAmountOut, Point memory bidPubKey) = abi.decode(auctionData_, (uint256, Point));

        // Validate inputs

        // Amount must be at least the minimum bid size at the minimum price
        uint256 minAmount = (uint256(auctionData[lotId_].minBidSize) * uint256(auctionData[lotId_].minPrice))/ (10 ** lotData[lotId_].baseTokenDecimals);
        if (amount_ < minAmount) revert Auction_AmountLessThanMinimum();

        // Check that the bid public key is a valid point for the encryption library
        if (!ECIES.isValid(bidPubKey)) revert Auction_InvalidKey();

        // Store bid data
        bidId = auctionData[lotId_].nextBidId++;
        Bid storage userBid = bids[lotId_][bidId];
        userBid.bidder = bidder_;
        userBid.amount = amount_;
        userBid.referrer = referrer_;
        userBid.status = BidStatus.Submitted;

        // Store encrypted amount out and bid public key
        encryptedBids[lotId_][bidId] = EncryptedBid(encryptedAmountOut, bidPubKey);

        // Push bid ID to list of bids to decrypt
        auctionData[lotId_].bidIds.push(bidId);

        return bidId;
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Marks the bid as refunded
    ///             - Removes the bid from the list of bids to decrypt
    ///             - Returns the amount to be refunded
    ///
    ///             The encrypted bid is not deleted from storage, so that the details can be fetched later.
    ///
    ///             This function reverts if:
    ///             - The bid is not in the Decrypted or Submitted state
    function _refundBid(
        uint96 lotId_,
        uint64 bidId_,
        address
    ) internal override returns (uint256 refund) {
        // Set bid status to claimed
        bids[lotId_][bidId_].status = BidStatus.Claimed;

        // Remove bid from list of bids to decrypt
        uint64[] storage bidIds = auctionData[lotId_].bidIds;
        uint256 len = bidIds.length;
        for (uint256 i; i < len; i++) {
            if (bidIds[i] == bidId_) {
                bidIds[i] = bidIds[len - 1];
                bidIds.pop();
                break;
            }
        }

        // Return the amount to be refunded
        return uint256(bids[lotId_][bidId_].amount);
    }

    function _claimBid(uint96 lotId_, uint64 bidId_) internal override returns (address referrer, uint256 paid, uint256 payout) {
        // Load bid data
        Bid storage bidData = bids[lotId_][bidId_];

        // Set the bid status to claimed
        bidData.status = BidStatus.Claimed;

        // Load the referrer
        referrer = bidData.referrer;

        // Calculate the bid price
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        uint256 price = bidData.minAmountOut == 0 ? 0 : (uint256(bidData.amount) * baseScale) / uint256(bidData.minAmountOut);

        // If the bid price is greater than or equal to the marginal price, the bid is filled
        // Auctions that do not meet capacity or price thresholds to settle will have their marginal price set at the maximum uint96
        // Therefore, all bids will be refunded.
        // We handle the only potential marginal fill during settlement. All other bids are either completely filled or refunded.
        uint256 marginalPrice = uint256(auctionData[lotId_].marginalPrice);
        if (price >= marginalPrice) {
            // Payout is calculated using the marginal price of the auction
            paid = uint256(bidData.amount);
            payout = (paid * baseScale) / marginalPrice;
        } else {
            // Bidder is refunded the paid amount and receives no payout
            paid = uint256(bidData.amount);
        }

    }

    // ========== DECRYPTION ========== //

    /// @notice         Submits the private key for the auction lot and decrypts an initial number of bids
    ///                 It does not require gating. If the owner wishes to limit who can call, they can simply not reveal the key to anyone else.
    ///                 On the other hand, if a key management service is used, then anyone can call it once the key is revealed.
    ///
    /// @dev            This function reverts if:
    ///                 - The lot ID is invalid
    ///                 - The lot is not active
    ///                 - The lot has not concluded
    ///                 - The private key has already been submitted
    function submitPrivateKey(uint96 lotId_, uint256 privateKey_, uint64 num_) external {
        // Validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotActive(lotId_);
        _revertIfBeforeLotStart(lotId_);

        // Revert if the private key has already been verified and set
        if (auctionData[lotId_].privateKey != 0) revert Auction_WrongState();

        // Check that the private key is valid for the public key
        // We assume that all public keys are derived from the same generator: (1, 2)
        Point memory calcPubKey = ECIES.calcPubKey(Point(1, 2), privateKey_);
        Point memory pubKey = auctionData[lotId_].publicKey;
        if (calcPubKey.x != pubKey.x || calcPubKey.y != pubKey.y) revert Auction_InvalidKey();

        // Store the private key
        auctionData[lotId_].privateKey = privateKey_;

        // Decrypt and sort bids
        _decryptAndSortBids(lotId_, num_);
    }

    /// @notice         Decrypts a batch of bids and sorts them by price in descending order
    /// @dev            This function handles the following:
    ///                 - Performs state validation
    ///                 - Iterates over the encrypted bids:
    ///                     - Decrypts the bid
    ///                     - Ignores if the bid is incorrectly encrypted
    ///                     - Does not add to the sorted bid queue if the decrypted amount out is less than the minimum bid size or overflows
    ///                     - Otherwise, adds to the sorted bid queue for use during settlement
    ///                 - Determines the next decrypt index
    ///                 - Sets the auction status to decrypted if all bids have been decrypted
    ///
    ///                 This function reverts if:
    ///                 - The lot ID is invalid
    ///                 - The lot has not concluded
    ///                 - The lot has already been decrypted in full
    ///                 - The private key has not been provided
    ///
    /// @param          lotId_          The lot ID of the auction to decrypt bids for
    /// @param          num_            The number of bids to decrypt. Reduced to the number remaining if greater.
    function decryptAndSortBids(uint96 lotId_, uint64 num_) external {
        // Check that lotId is valid
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotActive(lotId_);

        // Revert if already decrypted or if the private key has not been provided
        if (auctionData[lotId_].status != Auction.Status.Created || auctionData[lotId_].privateKey == 0) {
            revert Auction_WrongState();
        }

        // Decrypt and sort bids
        _decryptAndSortBids(lotId_, num_);
    }

    function _decryptAndSortBids(uint96 lotId_, uint64 num_) internal {
        // Load next decrypt index and min bid size
        AuctionData storage lotBidData = auctionData[lotId_];
        uint64 nextDecryptIndex = lotBidData.nextDecryptIndex;
        uint96 minBidSize = auctionData[lotId_].minBidSize;

        // Check that the number of decrypts is less than or equal to the number of bids remaining to be decrypted
        // If so, reduce to the number remaining
        uint64[] storage bidIds = auctionData[lotId_].bidIds;
        if (num_ > bidIds.length - nextDecryptIndex) {
            num_ = uint64(bidIds.length) - nextDecryptIndex;
        }

        // Iterate over the provided number of bids, decrypt them, and then store them in the sorted bid queue
        for (uint64 i; i < num_; i++) {
            // Load encrypted bid
            uint64 bidId = bidIds[nextDecryptIndex + i];

            // Decrypt the bid
            uint96 amountOut;
            {
                uint256 result = _decrypt(lotId_, bidId, lotBidData.privateKey);
                // We skip the bid if the decrypted amount out overflows the uint96 type
                // No valid bid should expect more than 7.9 * 10^28 (79 trillion tokens if 18 decimals)
                if (result > type(uint96).max) continue;
                amountOut = uint96(result);
            }

            // Set bid status to decrypted
            Bid storage bidData = bids[lotId_][bidId];
            bidData.status = BidStatus.Decrypted;

            // Only store the decrypt if the amount out is greater than or equal to the minimum bid size
            if (amountOut > 0 && amountOut >= minBidSize) {
                // Only store the decrypt if the price does not overflow
                if (
                    (
                        (uint256(bidData.amount) * 10 ** lotData[lotId_].baseTokenDecimals)
                            / uint256(amountOut)
                    ) < type(uint96).max
                ) {
                    // Store the decrypt in the sorted bid queue and set the min amount out on the bid
                    decryptedBids[lotId_].insert(bidId, bidData.amount, amountOut);
                    bidData.minAmountOut = amountOut;
                }
            }

            // Emit event
            emit BidDecrypted(lotId_, bidId, bidData.amount, amountOut);
        }

        // Increment next decrypt index
        auctionData[lotId_].nextDecryptIndex += num_;

        // If all bids have been decrypted, set auction status to decrypted
        if (auctionData[lotId_].nextDecryptIndex == bidIds.length) {
            auctionData[lotId_].status = Auction.Status.Decrypted;
        }
    }

    function _decrypt(
        uint96 lotId_,
        uint64 bidId_,
        uint256 privateKey_
    ) internal view returns (uint256 amountOut) {
        // Load the encrypted bid data
        EncryptedBid memory encryptedBid = encryptedBids[lotId_][bidId_];

        // Decrypt the message
        // We expect a salt calculated as the keccak256 hash of lot id, bidder, and amount to provide some (not total) uniqueness to the encryption, even if the same shared secret is used
        Bid storage bidData = bids[lotId_][bidId_];
        uint256 message = ECIES.decrypt(
            encryptedBid.encryptedAmountOut,
            encryptedBid.bidPubKey,
            privateKey_,
            uint256(keccak256(abi.encodePacked(lotId_, bidData.bidder, bidData.amount)))
        );

        // Convert the message into the amount out
        // We don't need larger than 16 bytes for a message
        // To avoid attacks that check for leading zero values, encrypted bids should use a 128-bit random number
        // as a seed to randomize the message. The seed should be the first 16 bytes.
        // During encryption, we subtract the seed from the amount out to get a masked value.
        // After decryption, we can combine them again (adding the seed to the masked value) and get the amount out
        // This works due to the overflow/underflow properties of modular arithmetic
        uint128 maskedValue = uint128(message);
        uint128 seed = uint128(message >> 128);

        // We want to allow underflow here
        unchecked {
            amountOut = uint256(maskedValue + seed);
        }
    }

    // ========== SETTLEMENT ========== //
    
    function _settle(uint96 lotId_) internal override returns (Settlement memory settlement_) {
        // Settle the auction
        // Check that auction is in the right state for settlement
        if (auctionData[lotId_].status != Auction.Status.Decrypted) revert Auction_WrongState();

        // Calculate marginal price and number of winning bids
        // Cache capacity and scaling values
        // Capacity is always in base token units for this auction type
        uint256 capacity = lotData[lotId_].capacity;
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        uint256 minimumPrice = auctionData[lotId_].minPrice;

        // Iterate over bid queue (sorted in descending price) to calculate the marginal clearing price of the auction
        uint256 marginalPrice;
        uint256 totalAmountIn;
        uint256 capacityExpended;
        uint64 partialFillBidId;
        {
            Queue storage queue = decryptedBids[lotId_];
            uint256 numBids = queue.getNumBids();
            uint256 lastPrice;
            for (uint256 i = 0; i < numBids; i++) {
                // Load bid info (in quote token units)
                uint64 bidId = queue.getMaxId();
                QueueBid memory qBid = queue.delMax();

                // A bid can be considered if:
                // - the bid price is greater than or equal to the minimum
                // - previous bids did not fill the capacity
                //
                // There is no need to check if the bid is the minimum bid size, as this was checked during decryption

                // Calculate the price of the bid
                uint256 price = (uint256(qBid.amountIn) * baseScale) / uint256(qBid.minAmountOut);

                // If the price is below the minimum price, the previous price is the marginal price
                if (price < minimumPrice) {
                    marginalPrice = lastPrice;
                    break;
                }

                // The current price will now be considered, so we can set this
                lastPrice = price;

                // Increment total amount in
                totalAmountIn += qBid.amountIn;

                // Determine total capacity expended at this price (in base token units)
                // quote scale * base scale / quote scale = base scale
                capacityExpended = (totalAmountIn * baseScale) / price;

                // If total capacity expended is greater than or equal to the capacity, we have found the marginal price
                if (capacityExpended >= capacity) {
                    marginalPrice = price;
                    if (capacityExpended > capacity) {
                        partialFillBidId = bidId;
                    }
                    break;
                }

                // If we have reached the end of the queue, we have found the marginal price and the maximum capacity that can be filled
                if (i == numBids - 1) {
                    marginalPrice = price;
                }
            }
        }

        // Delete the rest of the decrypted bids queue for a gas refund
        // TODO make sure this iteration doesn't cause out of gas issues, but it shouldn't due to the storage refunds
        {
            Queue storage queue = decryptedBids[lotId_];
            uint256 remainingBids = queue.getNumBids();
            if (remainingBids > 0) {
                for (uint256 i = remainingBids - 1; i >= 0; i--) {
                    uint64 bidId = queue.bidIdList[i];
                    delete queue.idToBidMap[bidId];
                    queue.bidIdList.pop();

                    // Otherwise an underflow will occur
                    if (i == 0) {
                        break;
                    }
                }
                delete queue.numBids;
            }
        }

        // Determine if the auction can be filled, if so settle the auction, otherwise refund the seller
        // We set the status as settled either way to denote this function has been executed
        auctionData[lotId_].status = Auction.Status.Settled;
        // Auction cannot be settled if the total filled is less than the minimum filled
        // or if the marginal price is less than the minimum price
        if (capacityExpended >= auctionData[lotId_].minFilled && marginalPrice >= minimumPrice) {
            // Auction can be settled at the marginal price if we reach this point
            // TODO determine if this can overflow
            auctionData[lotId_].marginalPrice = uint96(marginalPrice);

            // If there is a partially filled bid, set refund and payout for the bid and mark as claimed
            if (partialFillBidId != 0) {
                // Load routing and bid data
                Bid storage bidData = bids[lotId_][partialFillBidId];

                // Set the bidder on for the partially filled bid
                settlement_.pfBidder = bidData.bidder;

                // Calculate the payout and refund amounts
                uint256 fullFill = (uint256(bidData.amount) * baseScale) / marginalPrice;
                uint256 excess = capacityExpended - capacity;
                settlement_.pfPayout = fullFill - excess;
                settlement_.pfRefund = (uint256(bidData.amount) * excess) / fullFill;

                // Reduce the total amount in by the refund amount
                totalAmountIn -= settlement_.pfRefund;

                // Set bid as claimed
                bidData.status = BidStatus.Claimed;
            }

            // Set settlement data
            settlement_.totalIn = totalAmountIn;
            settlement_.totalOut = capacityExpended > capacity ? capacity : capacityExpended;
        } else {
            // Auction cannot be settled if we reach this point
            // Marginal price is set as the max uint96 for the auction so the system knows all bids should be refunded
            auctionData[lotId_].marginalPrice = type(uint96).max;

            // totalIn and totalOut are not set since the auction does not clear
        }
    }

    // ========== VALIDATION ========== //
    // TODO

}
