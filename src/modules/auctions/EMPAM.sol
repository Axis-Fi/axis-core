// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// Protocol dependencies
import {AuctionModule, Auction} from "src/modules/Auction.sol";
import {Veecode, toVeecode} from "src/modules/Modules.sol";

// Libraries
import {FixedPointMathLib as Math} from "lib/solmate/src/utils/FixedPointMathLib.sol";
import {ECIES, Point} from "src/lib/ECIES.sol";
import {MaxPriorityQueue, Queue, Bid as QueueBid} from "src/lib/MaxPriorityQueue.sol";

contract EncryptedMarginalPriceAuctionModule is AuctionModule {
    using MaxPriorityQueue for Queue;

    // ========== ERRORS ========== //
    error Auction_InvalidKey();
    error Auction_WrongState(uint96 lotId); // TODO shift into Auction?
    error Bid_WrongState(uint96 lotId, uint64 bidId);
    error NotPermitted(address caller);

    // ========== EVENTS ========== //
    event BidDecrypted(
        uint96 indexed lotId, uint64 indexed bidId, uint96 amountIn, uint96 amountOut
    );

    // ========== DATA STRUCTURES ========== //

    enum BidStatus {
        Submitted,
        Decrypted,
        // Bid status will also be set to claimed if the bid is cancelled/refunded
        Claimed
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
        Auction.Status status; // 1 +
        uint64 marginalBidId; // 8 = 9 - end of slot 3
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

    /// @dev    Memory only, no need to pack
    struct MarginalPriceResult {
        uint96 marginalPrice;
        uint64 marginalBidId;
        uint64 partialFillBidId;
        uint256 totalAmountIn;
        uint256 capacityExpended;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice Constant for percentages
    /// @dev    1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint24 internal constant _MIN_BID_PERCENT = 10; // 0.01%

    /// @notice     Auction-specific data for a lot
    mapping(uint96 lotId => AuctionData) public auctionData;

    /// @notice     General information about bids on a lot
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

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes:
    ///             - The lot ID has been validated
    ///             - The start and duration of the lot have been validated
    ///
    ///             This function reverts if:
    ///             - The parameters cannot be decoded into the correct format
    ///             - The minimum price is zero
    ///             - The minimum fill percent is greater than 100%
    ///             - The minimum bid percent is less than the minimum or greater than 100%
    ///             - The public key is not valid
    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override {
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
        // We round up to be conservative with the minimums
        data.minFilled = uint96(
            Math.mulDivUp(
                uint256(lot_.capacity),
                uint256(implParams.minFillPercent),
                uint256(_ONE_HUNDRED_PERCENT)
            )
        );
        data.minBidSize = uint96(
            Math.mulDivUp(
                uint256(lot_.capacity), implParams.minBidPercent, uint256(_ONE_HUNDRED_PERCENT)
            )
        );
        data.publicKey = implParams.publicKey;
        data.nextBidId = 1;

        decryptedBids[lotId_].initialize();
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes the following:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction has not concluded
    ///
    ///             This function reverts if:
    ///             - The auction is active or has not concluded
    function _cancelAuction(uint96 lotId_) internal override {
        // Validation
        // Batch auctions cannot be cancelled once started, otherwise the seller could cancel the auction after bids have been submitted
        _revertIfLotActive(lotId_);

        // Set auction status to claimed so that bids can be refunded
        auctionData[lotId_].status = Auction.Status.Claimed;
    }

    // ========== BID ========== //

    /// @inheritdoc AuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Stores the encrypted bid
    ///             - Adds the bid ID to the list of bids to decrypt (in `AuctionData.bidIds`)
    ///             - Returns the bid ID
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is active
    ///
    ///             This function reverts if:
    ///             - The parameters cannot be decoded into the correct format
    ///             - The amount is less than the minimum bid size for the lot
    ///             - The bid public key is not valid
    function _bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint96 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint64 bidId) {
        // Decode auction data
        (uint256 encryptedAmountOut, Point memory bidPubKey) =
            abi.decode(auctionData_, (uint256, Point));

        // Validate inputs

        // Amount must be at least the minimum bid size at the minimum price
        uint256 minAmount = Math.mulDivDown(
            uint256(auctionData[lotId_].minBidSize),
            uint256(auctionData[lotId_].minPrice),
            10 ** lotData[lotId_].baseTokenDecimals
        );
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
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The bid ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is active
    ///             - The bid has already been refunded
    function _refundBid(
        uint96 lotId_,
        uint64 bidId_,
        address
    ) internal override returns (uint96 refund) {
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
        return bids[lotId_][bidId_].amount;
    }

    /// @notice     Claims a bid and calculates the paid and payout amounts
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Marks the bid as claimed
    ///             - Calculates the paid and payout amounts
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The bid ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is not settled
    ///             - The bid has not already been claimed
    function _claimBid(
        uint96 lotId_,
        uint64 bidId_
    ) internal returns (BidClaim memory bidClaim, bytes memory auctionOutput_) {
        // Load bid data
        Bid storage bidData = bids[lotId_][bidId_];

        // Set the bid status to claimed
        bidData.status = BidStatus.Claimed;

        // Load the referrer and bidder
        bidClaim.bidder = bidData.bidder;
        bidClaim.referrer = bidData.referrer;

        // Calculate the bid price
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        uint96 price = uint96(
            bidData.minAmountOut == 0
                ? 0 // TODO technically minAmountOut == 0 should be an infinite price, but need to check that later. Need to be careful we don't introduce a way to claim a bid when we set marginalPrice to type(uint96).max when it cannot be settled.
                : Math.mulDivUp(uint256(bidData.amount), baseScale, uint256(bidData.minAmountOut))
        );

        // If the bid price is greater than the marginal price, the bid is filled.
        // If the bid price is equal to the marginal price and the bid was submitted before or is the marginal bid, the bid is filled.
        // Auctions that do not meet capacity or price thresholds to settle will have their marginal price set at the maximum uint96
        // Therefore, all bids will be refunded.
        // We handle the only potential marginal fill during settlement. All other bids are either completely filled or refunded.
        uint96 marginalPrice = auctionData[lotId_].marginalPrice;
        if (
            price > marginalPrice
                || (price == marginalPrice && bidId_ <= auctionData[lotId_].marginalBidId)
        ) {
            // Payout is calculated using the marginal price of the auction
            bidClaim.paid = bidData.amount;
            bidClaim.payout = uint96(Math.mulDivDown(bidClaim.paid, baseScale, marginalPrice));
        } else {
            // Bidder is refunded the paid amount and receives no payout
            bidClaim.paid = bidData.amount;
        }

        return (bidClaim, auctionOutput_);
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Marks the bid as claimed
    ///             - Calculates the paid and payout amounts
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is not settled
    function _claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    ) internal override returns (BidClaim[] memory bidClaims, bytes memory auctionOutput_) {
        uint256 len = bidIds_.length;
        bidClaims = new BidClaim[](len);
        for (uint256 i; i < len; i++) {
            // Validate
            _revertIfBidInvalid(lotId_, bidIds_[i]);
            _revertIfBidClaimed(lotId_, bidIds_[i]);

            (bidClaims[i],) = _claimBid(lotId_, bidIds_[i]);
        }

        return (bidClaims, auctionOutput_);
    }

    // ========== DECRYPTION ========== //

    /// @notice         Submits the private key for the auction lot and decrypts an initial number of bids
    ///                 It does not require gating. If the seller wishes to limit who can call, they can simply not reveal the key to anyone else.
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
        if (auctionData[lotId_].privateKey != 0) revert Auction_WrongState(lotId_);

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
        if (
            auctionData[lotId_].status != Auction.Status.Created
                || auctionData[lotId_].privateKey == 0
        ) {
            revert Auction_WrongState(lotId_);
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
        // All submitted bids will be marked as decrypted, but only those with valid values will have the minAmountOut set and be stored in the sorted bid queue
        for (uint64 i; i < num_; i++) {
            // Load encrypted bid
            uint64 bidId = bidIds[nextDecryptIndex + i];

            // Decrypt the bid
            uint96 amountOut;
            {
                uint256 result = _decrypt(lotId_, bidId, lotBidData.privateKey);

                // Only set the amount out if it is less than or equal to the maximum value of a uint96
                if (result <= type(uint96).max) {
                    amountOut = uint96(result);
                }
            }

            // Set bid status to decrypted
            Bid storage bidData = bids[lotId_][bidId];
            bidData.status = BidStatus.Decrypted;

            // Only store the decrypt if the amount out is greater than or equal to the minimum bid size
            if (amountOut > 0 && amountOut >= minBidSize) {
                // Only store the decrypt if the price does not overflow
                // We don't need to check for a zero bid price, because the smallest possible bid price is 1, due to the use of mulDivUp
                // 1 * 10^6 / type(uint96).max = 1
                if (
                    Math.mulDivUp(
                        uint256(bidData.amount),
                        10 ** lotData[lotId_].baseTokenDecimals,
                        uint256(amountOut)
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

    /// @notice         Helper function to get the next bid from the queue and calculate the price
    /// @dev            This is split into a different function to avoid stack too deep errors
    ///
    /// @param          queue_          The queue to get the next bid from
    /// @param          baseScale_      The scaling factor for the base token
    /// @return         bidId           The ID of the bid
    /// @return         amountIn        The amount in of the bid (in quote token units)
    /// @return         price           The price of the bid (in quote token units), or 0 if it could not be determined
    function _getNextBid(
        Queue storage queue_,
        uint256 baseScale_
    ) internal returns (uint64 bidId, uint96 amountIn, uint96 price) {
        bidId = queue_.getMaxId();

        // Load bid info (in quote token units)
        QueueBid memory qBid = queue_.delMax();
        amountIn = qBid.amountIn;

        // A zero minAmountOut value should be filtered out during decryption. However, cover the case here to avoid a potential division by zero error that would brick settlement.
        if (qBid.minAmountOut == 0) {
            // A zero price would be filtered out being below the minimum price
            return (bidId, amountIn, 0);
        }

        // Calculate the price of the bid
        // Cannot overflow on cast back to uint96. It was checked during decryption.
        price = uint96(Math.mulDivUp(amountIn, baseScale_, qBid.minAmountOut));

        return (bidId, amountIn, price);
    }

    /// @notice     Calculates the marginal price of a lot
    ///
    /// @param      lotId_          The lot ID of the auction to calculate the marginal price for
    /// @return     result          The result of the marginal price calculation
    function _getLotMarginalPrice(uint96 lotId_)
        internal
        returns (MarginalPriceResult memory result)
    {
        // Cache values used in the loop
        // Capacity is always in base token units for this auction type
        uint256 capacity = lotData[lotId_].capacity;
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        AuctionData memory lotAuctionData = auctionData[lotId_];

        // Iterate over bid queue (sorted in descending price) to calculate the marginal clearing price of the auction
        {
            Queue storage queue = decryptedBids[lotId_];
            uint96 lastPrice;
            uint64 lastBidId;
            uint256 numBids = queue.getNumBids();
            for (uint256 i = 0; i < numBids; i++) {
                // A bid can be considered if:
                // - the bid price is greater than or equal to the minimum
                // - previous bids did not fill the capacity
                //
                // There is no need to check if the bid is the minimum bid size, as this was checked during decryption

                // Get bid info
                (uint64 bidId, uint96 amountIn, uint96 price) = _getNextBid(queue, baseScale);

                // If the price is below the minimum price, then determine a marginal price from the previous bids with the knowledge that no other bids will be considered
                // This will also handle a zero price returned from `_getNextBid()`, since `minPrice` is always greater than zero
                if (price < lotAuctionData.minPrice) {
                    // We know that the lastPrice was not sufficient to fill capacity or the loop would have exited
                    // We check if minimum price can result in a fill. If so, find the exact marginal price between last price and minimum price
                    // If not, we set the marginal price to the minimum price. Whether the capacity filled meets the minimum filled will be checked later in the settlement process.
                    if (
                        lotAuctionData.minPrice == 0
                            || Math.mulDivDown(result.totalAmountIn, baseScale, lotAuctionData.minPrice)
                                >= capacity
                    ) {
                        result.marginalPrice =
                            uint96(Math.mulDivUp(result.totalAmountIn, baseScale, capacity));
                    } else {
                        result.marginalPrice = lotAuctionData.minPrice; // note this cannot be zero since it is checked above
                    }

                    // If the marginal price is re-calculated and is the same as the previous, we need to set the marginal bid id, otherwise the previous bid will not be able to claim.
                    if (lastPrice == result.marginalPrice) {
                        result.marginalBidId = lastBidId;
                    }

                    // Update capacity expended with the new marginal price
                    result.capacityExpended = Math.mulDivDown(
                        result.totalAmountIn, baseScale, uint256(result.marginalPrice)
                    );
                    // marginal bid id can be zero, there are no bids at the marginal price

                    // Exit the outer loop
                    break;
                }

                // Check if the auction can clear with the existing bids at a price between current price and last price
                // There will be no partial fills because we select the price that exactly fills the capacity
                // Note: totalAmountIn here has not had the current bid added to it
                result.capacityExpended = Math.mulDivDown(result.totalAmountIn, baseScale, price);
                if (result.capacityExpended >= capacity) {
                    result.marginalPrice =
                        uint96(Math.mulDivUp(result.totalAmountIn, baseScale, capacity));

                    // If the marginal price is re-calculated and is the same as the previous, we need to set the marginal bid id, otherwise the previous bid will not be able to claim.
                    if (lastPrice == result.marginalPrice) {
                        result.marginalBidId = lastBidId;
                    } else {
                        result.marginalBidId = uint64(0); // we set this to zero so that any bids at the current price are not considered in the case that capacityExpended == capacity
                    }

                    // Calculate the capacity expended in the same way as before, instead of setting it to `capacity`
                    // This will normally equal `capacity`, except when rounding would cause the the capacity expended to be slightly less than `capacity`
                    result.capacityExpended =
                        Math.mulDivDown(result.totalAmountIn, baseScale, result.marginalPrice); // updated based on the marginal price
                    break;
                }

                // The current price will now be considered, so we can set this
                lastPrice = price;
                lastBidId = bidId;

                // Increment total amount in
                result.totalAmountIn += amountIn;

                // Determine total capacity expended at this price (in base token units)
                // quote scale * base scale / quote scale = base scale
                result.capacityExpended =
                    Math.mulDivDown(result.totalAmountIn, baseScale, uint256(price));

                // If total capacity expended is greater than or equal to the capacity, we have found the marginal price
                // If capacity expended is strictly greater than capacity, then we have a partially filled bid
                if (result.capacityExpended >= capacity) {
                    result.marginalPrice = price;
                    result.marginalBidId = bidId;
                    if (result.capacityExpended > capacity) {
                        result.partialFillBidId = bidId;
                    }
                    break;
                }

                // If we have reached the end of the queue, we check the same cases as when the price of a bid is below the minimum price.
                if (i == numBids - 1) {
                    // We know that the price was not sufficient to fill capacity or the loop would have exited
                    // We check if minimum price can result in a complete fill. If so, find the exact marginal price between last price and minimum price
                    // If not, we set the marginal price to the minimum price. Whether the capacity filled meets the minimum filled will be checked later in the settlement process
                    if (
                        lotAuctionData.minPrice == 0
                            || Math.mulDivDown(result.totalAmountIn, baseScale, lotAuctionData.minPrice)
                                >= capacity
                    ) {
                        result.marginalPrice =
                            uint96(Math.mulDivUp(result.totalAmountIn, baseScale, capacity));
                    } else {
                        result.marginalPrice = lotAuctionData.minPrice;
                    }

                    // If the marginal price is re-calculated and is the same as the previous, we need to set the marginal bid id, otherwise the current bid will not be able to claim.
                    if (price == result.marginalPrice) {
                        result.marginalBidId = bidId;
                    }

                    result.capacityExpended = Math.mulDivDown(
                        result.totalAmountIn, baseScale, uint256(result.marginalPrice)
                    );
                    // marginal bid id can be zero, there are no bids at the marginal price
                }
            }
        }

        return result;
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Iterates over the decrypted bids to calculate the marginal price and number of winning bids
    ///             - If applicable, calculates the payout and refund for a partially filled bid
    ///             - Sets the auction status to settled
    ///             - Deletes the remaining decrypted bids for a gas refund
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The auction has concluded
    ///             - The auction is not settled
    ///
    ///             This function reverts if:
    ///             - The auction has not been decrypted
    ///
    ///             The function has been written to avoid any reverts that would cause the settlement process to brick.
    function _settle(uint96 lotId_)
        internal
        override
        returns (Settlement memory settlement_, bytes memory auctionOutput_)
    {
        // Settle the auction
        // Check that auction is in the right state for settlement
        if (auctionData[lotId_].status != Auction.Status.Decrypted) {
            revert Auction_WrongState(lotId_);
        }

        MarginalPriceResult memory result = _getLotMarginalPrice(lotId_);

        // Calculate marginal price and number of winning bids
        // Cache capacity and scaling values
        // Capacity is always in base token units for this auction type
        uint256 capacity = lotData[lotId_].capacity;
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        AuctionData memory lotAuctionData = auctionData[lotId_];

        // Delete the rest of the decrypted bids queue for a gas refund
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
        if (
            result.capacityExpended >= auctionData[lotId_].minFilled
                && result.marginalPrice >= lotAuctionData.minPrice
        ) {
            // Auction can be settled at the marginal price if we reach this point
            auctionData[lotId_].marginalPrice = result.marginalPrice;
            auctionData[lotId_].marginalBidId = result.marginalBidId;

            // If there is a partially filled bid, set refund and payout for the bid and mark as claimed
            if (result.partialFillBidId != 0) {
                // Load routing and bid data
                Bid storage bidData = bids[lotId_][result.partialFillBidId];

                // Set the bidder on for the partially filled bid
                settlement_.pfBidder = bidData.bidder;
                settlement_.pfReferrer = bidData.referrer;

                // Calculate the payout and refund amounts
                uint256 fullFill =
                    Math.mulDivDown(uint256(bidData.amount), baseScale, result.marginalPrice);
                uint256 excess = result.capacityExpended - capacity;
                settlement_.pfPayout = uint96(fullFill - excess);
                settlement_.pfRefund =
                    uint96(Math.mulDivDown(uint256(bidData.amount), excess, fullFill));

                // Reduce the total amount in by the refund amount
                result.totalAmountIn -= settlement_.pfRefund;

                // Set bid as claimed
                bidData.status = BidStatus.Claimed;
            }

            // Set settlement data
            // TODO think about casting checks
            settlement_.totalIn = uint96(result.totalAmountIn);
            settlement_.totalOut =
                uint96(result.capacityExpended > capacity ? capacity : result.capacityExpended);
        } else {
            // Auction cannot be settled if we reach this point
            // Marginal price is set as the max uint96 for the auction so the system knows all bids should be refunded
            auctionData[lotId_].marginalPrice = type(uint96).max;

            // totalIn and totalOut are not set since the auction does not clear
        }

        return (settlement_, auctionOutput_);
    }

    /// @inheritdoc AuctionModule
    function _claimProceeds(uint96 lotId_)
        internal
        override
        returns (uint96 purchased, uint96 sold, uint96 payoutSent)
    {
        // Update the status
        auctionData[lotId_].status = Auction.Status.Claimed;

        // Get the lot data
        Lot memory lot = lotData[lotId_];

        // Return the required data
        return (lot.purchased, lot.sold, lot.partialPayout);
    }

    // ========== AUCTION INFORMATION ========== //

    function getBid(
        uint96 lotId_,
        uint64 bidId_
    ) external view returns (Bid memory bid, EncryptedBid memory encryptedBid) {
        _revertIfLotInvalid(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);

        return (bids[lotId_][bidId_], encryptedBids[lotId_][bidId_]);
    }

    function getAuctionData(uint96 lotId_)
        external
        view
        returns (AuctionData memory auctionData_)
    {
        _revertIfLotInvalid(lotId_);

        return auctionData[lotId_];
    }

    /// @inheritdoc Auction
    function auctionType() external pure override returns (AuctionType) {
        return AuctionType.Batch;
    }

    // ========== VALIDATION ========== //

    /// @inheritdoc AuctionModule
    function _revertIfLotActive(uint96 lotId_) internal view override {
        if (
            auctionData[lotId_].status == Auction.Status.Created
                && lotData[lotId_].start <= block.timestamp
                && lotData[lotId_].conclusion > block.timestamp
        ) revert Auction_WrongState(lotId_);
    }

    /// @inheritdoc AuctionModule
    function _revertIfLotSettled(uint96 lotId_) internal view override {
        // Auction must not be settled
        if (auctionData[lotId_].status == Auction.Status.Settled) {
            revert Auction_WrongState(lotId_);
        }
    }

    /// @inheritdoc AuctionModule
    function _revertIfLotNotSettled(uint96 lotId_) internal view override {
        // Auction must be settled
        if (auctionData[lotId_].status != Auction.Status.Settled) {
            revert Auction_WrongState(lotId_);
        }
    }

    /// @inheritdoc AuctionModule
    function _revertIfLotProceedsClaimed(uint96 lotId_) internal view override {
        // Auction must not have proceeds claimed
        if (auctionData[lotId_].status == Auction.Status.Claimed) {
            revert Auction_WrongState(lotId_);
        }
    }

    /// @inheritdoc AuctionModule
    function _revertIfBidInvalid(uint96 lotId_, uint64 bidId_) internal view override {
        // Bid ID must be less than number of bids for lot
        if (bidId_ >= auctionData[lotId_].nextBidId) revert Auction_InvalidBidId(lotId_, bidId_);

        // Bid should have a bidder
        if (bids[lotId_][bidId_].bidder == address(0)) revert Auction_InvalidBidId(lotId_, bidId_);
    }

    /// @inheritdoc AuctionModule
    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) internal view override {
        // Check that sender is the bidder
        if (caller_ != bids[lotId_][bidId_].bidder) revert NotPermitted(caller_);
    }

    /// @inheritdoc AuctionModule
    function _revertIfBidClaimed(uint96 lotId_, uint64 bidId_) internal view override {
        // Bid must not be refunded or claimed (same status)
        if (bids[lotId_][bidId_].status == BidStatus.Claimed) {
            revert Bid_WrongState(lotId_, bidId_);
        }
    }

    // ========== NOT IMPLEMENTED ========== //

    function _purchase(
        uint96,
        uint96,
        bytes calldata
    ) internal pure override returns (uint96, bytes memory) {
        revert Auction_NotImplemented();
    }
}
