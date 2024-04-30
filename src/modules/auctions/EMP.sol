// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IBatchAuction} from "src/interfaces/IBatchAuction.sol";

// Internal libraries
import {ECIES, Point} from "src/lib/ECIES.sol";
import {MaxPriorityQueue, Queue} from "src/lib/MaxPriorityQueue.sol";

// External libraries
import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";

// Auctions
import {AuctionModule} from "src/modules/Auction.sol";
import {BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";

import {Veecode, toVeecode} from "src/modules/Modules.sol";

/// @notice     Encrypted Marginal Price
/// @dev        This batch auction module allows for bids to be encrypted off-chain, then stored, decrypted and settled on-chain.
///
///             Note that the maximum bid amount is bounded by uint96.
contract EncryptedMarginalPrice is BatchAuctionModule {
    using MaxPriorityQueue for Queue;

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

    /// @notice     The status of an auction lot
    enum LotStatus {
        Created,
        Decrypted,
        Settled
    }

    /// @notice     The status of a bid
    /// @dev        Bid status will also be set to claimed if the bid is cancelled/refunded
    enum BidStatus {
        Submitted,
        Decrypted,
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

    /// @notice         Parameters that are used to set auction-specific data
    ///
    /// @param          minPrice            The minimum price (in quote tokens) that a bid must fulfill
    /// @param          minFillPercent      The minimum percentage of capacity that the lot must fill in order to settle
    /// @param          minBidSize          The minimum size of a bid in quote tokens
    /// @param          publicKey           The public key used to encrypt bids
    struct AuctionDataParams {
        uint256 minPrice;
        uint24 minFillPercent;
        uint256 minBidSize;
        Point publicKey;
    }

    /// @notice Stuct containing the marginal price result
    /// @dev    Memory only, no need to pack
    ///
    /// @param  marginalPrice       The marginal price of the auction. Set only if the marginal price has been determined.
    /// @param  marginalBidId       The ID of the marginal bid (marking that bids following it are not filled). Set only if the marginal price has been determined and there is a need for this to be set.
    /// @param  lastBidId           The ID of the last bid processed during the marginal price calculation. This should always be set, regardless of the settlement outcome.
    /// @param  totalAmountIn       The total amount in from bids processed so far. This should always be set, regardless of the settlement outcome.
    /// @param  capacityExpended    The total capacity expended from bids processed so far. This should always be set, regardless of the settlement outcome.
    /// @param  finished            Whether settlement has been completed.
    struct MarginalPriceResult {
        uint256 marginalPrice;
        uint64 marginalBidId;
        uint64 lastBidId;
        uint256 totalAmountIn;
        uint256 capacityExpended;
        bool finished;
    }

    /// @notice Struct to store the data for in-progress settlement
    ///
    /// @param  processedAmountIn   The total amount in from bids processed so far (during settlement)
    /// @param  lastPrice           The last price processed during settlement
    /// @param  lastBidId           The ID of the last bid processed during settlement
    struct PartialSettlement {
        uint256 processedAmountIn;
        uint256 lastPrice;
        uint64 lastBidId;
    }

    /// @notice        Struct containing partial fill data for a lot
    ///
    /// @param         bidId        The ID of the bid
    /// @param         refund       The amount to refund to the bidder
    /// @param         payout       The amount to payout to the bidder
    struct PartialFill {
        uint64 bidId; // 8 +
        uint96 refund; // 12 = 20 - end of slot 1
        uint256 payout; // 32 - slot 2
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     Time period after auction conclusion where bidders cannot refund bids
    uint48 public dedicatedSettlePeriod;

    /// @notice     Auction-specific data for a lot
    mapping(uint96 lotId => AuctionData) public auctionData;

    /// @notice     Partial fill data for a lot
    /// @dev        Each EMPA can have at most one partial fill
    mapping(uint96 lotId => PartialFill) internal _lotPartialFill;

    /// @notice     Partial settlement data stored between settlement batches
    mapping(uint96 lotId => PartialSettlement) internal _lotPartialSettlement;

    /// @notice     General information about bids on a lot
    mapping(uint96 lotId => mapping(uint64 bidId => Bid)) public bids;

    /// @notice     Data for encryption information for a specific bid
    mapping(uint96 lotId => mapping(uint64 bidId => EncryptedBid)) public encryptedBids; // each encrypted amount is 4 slots (length + 3 slots)

    /// @notice     Queue of decrypted bids for a lot (populated on decryption)
    mapping(uint96 lotId => Queue) public decryptedBids;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day initially
        minAuctionDuration = 1 days;

        // Set the dedicated settle period to 1 day initially
        dedicatedSettlePeriod = 1 days;
    }

    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01EMPA");
    }

    // ========== MODIFIERS ========== //

    // ========== AUCTION ========== //

    /// @inheritdoc AuctionModule
    /// @dev        This function assumes:
    ///             - The lot ID has been validated
    ///             - The start and duration of the lot have been validated
    ///
    ///             This function performs the following:
    ///             - Validates the auction parameters
    ///             - Stores the auction data
    ///             - Initializes the decrypted bids queue
    ///
    ///             This function reverts if:
    ///             - The parameters cannot be decoded into the correct format
    ///             - The minimum price is zero
    ///             - The minimum fill percent is greater than 100%
    ///             - The minimum bid size is zero or greater than the max uint96 value
    ///             - The public key is not valid
    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override {
        // Decode implementation params
        AuctionDataParams memory implParams = abi.decode(params_, (AuctionDataParams));

        // Validate params

        // minPrice must not be zero
        if (implParams.minPrice == 0) revert Auction_InvalidParams();

        // minFillPercent must be less than or equal to 100%
        if (implParams.minFillPercent > _ONE_HUNDRED_PERCENT) revert Auction_InvalidParams();

        // minBidSize must be less than or equal to the max uint96 value and not zero
        if (implParams.minBidSize > type(uint96).max || implParams.minBidSize == 0) {
            revert Auction_InvalidParams();
        }

        // publicKey must be a valid point for the encryption library
        if (!ECIES.isValid(implParams.publicKey)) revert Auction_InvalidParams();

        // Set auction data
        AuctionData storage data = auctionData[lotId_];
        data.minPrice = implParams.minPrice;
        // We round up to be conservative with the minimums
        data.minFilled =
            Math.fullMulDivUp(lot_.capacity, implParams.minFillPercent, _ONE_HUNDRED_PERCENT);
        data.minBidSize = implParams.minBidSize;
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
    ///             This function performs the following:
    ///             - Sets the auction status to settled, and prevents claiming of proceeds
    ///
    ///             This function reverts if:
    ///             - The auction is active or has not concluded
    function _cancelAuction(uint96 lotId_) internal override {
        // Validation
        // Batch auctions cannot be cancelled once started, otherwise the seller could cancel the auction after bids have been submitted
        _revertIfLotActive(lotId_);

        // Set auction status to settled so that bids can be refunded
        auctionData[lotId_].status = LotStatus.Settled;
    }

    // ========== BID ========== //

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Stores the encrypted bid
    ///             - Adds the bid ID to the list of bids to decrypt
    ///             - Returns the bid ID
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is active
    ///
    ///             This function reverts if:
    ///             - The parameters cannot be decoded into the correct format
    ///             - The amount is greater than the max uint96 value
    ///             - The amount is less than the minimum bid size for the lot
    ///             - The bid public key is not valid
    function _bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint64 bidId) {
        // Decode auction data
        (uint256 encryptedAmountOut, Point memory bidPubKey) =
            abi.decode(auctionData_, (uint256, Point));

        // Validate inputs

        // Amount must be less than the max uint96 value for casting
        if (amount_ > type(uint96).max) revert Auction_InvalidParams();

        // Amount must be at least the minimum bid size
        if (amount_ < auctionData[lotId_].minBidSize) revert Auction_AmountLessThanMinimum();

        // Check that the bid public key is a valid point for the encryption library
        if (!ECIES.isValid(bidPubKey)) revert Auction_InvalidKey();

        // Store bid data
        bidId = auctionData[lotId_].nextBidId++;
        Bid storage userBid = bids[lotId_][bidId];
        userBid.bidder = bidder_;
        userBid.amount = uint96(amount_);
        userBid.referrer = referrer_;
        userBid.status = BidStatus.Submitted;

        // Store encrypted amount out and bid public key
        encryptedBids[lotId_][bidId] = EncryptedBid(encryptedAmountOut, bidPubKey);

        // Push bid ID to list of bids to decrypt
        auctionData[lotId_].bidIds.push(bidId);

        return bidId;
    }

    /// @inheritdoc IBatchAuction
    /// @dev        Implements a basic refundBid function that:
    ///             - Validates the lot and bid parameters
    ///             - Calls the implementation-specific function
    ///
    ///             This function reverts if:
    ///             - The lot id is invalid
    ///             - The lot has not started
    ///             - The lot is decrypted or settled (but not concluded)
    ///             - The lot is within the dedicated settle period
    ///             - The bid id is invalid
    ///             - `caller_` is not the bid owner
    ///             - The bid is claimed or refunded
    ///             - The caller is not an internal module
    ///
    ///             This is a modified version of the refundBid function in the AuctionModule contract.
    ///             It does not revert if the lot is concluded.
    function refundBid(
        uint96 lotId_,
        uint64 bidId_,
        uint256 index_,
        address caller_
    ) external override onlyInternal returns (uint256 refund) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);
        _revertIfNotBidOwner(lotId_, bidId_, caller_);
        _revertIfBidClaimed(lotId_, bidId_);
        _revertIfDedicatedSettlePeriod(lotId_);
        _revertIfKeySubmitted(lotId_);
        _revertIfLotSettled(lotId_);

        // Call implementation-specific logic
        return _refundBid(lotId_, bidId_, index_, caller_);
    }

    /// @inheritdoc BatchAuctionModule
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
        uint256 index_,
        address
    ) internal override returns (uint256 refund) {
        // Set bid status to claimed
        bids[lotId_][bidId_].status = BidStatus.Claimed;

        // Remove bid from list of bids to decrypt
        uint64[] storage bidIds = auctionData[lotId_].bidIds;
        uint256 len = bidIds.length;

        // Validate that the index is within bounds
        if (index_ >= len) revert Auction_InvalidParams();

        // Load the bid ID to remove and confirm it matches the provided one
        uint64 bidId = bidIds[index_];
        if (bidId != bidId_) revert Auction_InvalidParams();

        // Remove the bid ID from the list
        bidIds[index_] = bidIds[len - 1];
        bidIds.pop();

        // Return the amount to be refunded
        return uint256(bids[lotId_][bidId_].amount);
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
        uint256 price = bidData.minAmountOut == 0
            ? 0 // Set price to zero for this bid since it was invalid
            : Math.mulDivUp(bidData.amount, baseScale, bidData.minAmountOut);

        uint256 marginalPrice = auctionData[lotId_].marginalPrice;

        // If the bidId matches the partial fill for the lot, assign the stored data.
        // Otherwise,
        // If the bid price is greater than the marginal price, the bid is filled.
        // If the bid price is equal to the marginal price and the bid was submitted before or is the marginal bid, the bid is filled.
        // Auctions that do not meet capacity or price thresholds to settle will have their marginal price set at the maximum uint96
        // and there will be no partial fill. Therefore, all bids will be refunded.
        if (_lotPartialFill[lotId_].bidId == bidId_) {
            bidClaim.paid = bidData.amount;
            bidClaim.payout = _lotPartialFill[lotId_].payout;
            bidClaim.refund = _lotPartialFill[lotId_].refund;
        } else if (
            price > marginalPrice
                || (price == marginalPrice && bidId_ <= auctionData[lotId_].marginalBidId)
        ) {
            // Payout is calculated using the marginal price of the auction
            bidClaim.paid = bidData.amount;
            bidClaim.payout = Math.mulDiv(bidClaim.paid, baseScale, marginalPrice);
        } else {
            // Bidder is refunded the paid amount and receives no payout
            bidClaim.paid = bidData.amount;
            bidClaim.refund = bidData.amount;
        }

        return (bidClaim, auctionOutput_);
    }

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Marks the bid as claimed
    ///             - Calculates the paid and payout amounts
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The caller has been authorized
    ///             - The auction is not settled
    ///
    ///             This function reverts if:
    ///             - The bid ID is invalid
    ///             - The bid has already been claimed
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
    ///                 This function reverts if:
    ///                 - The lot ID is invalid
    ///                 - The lot is not active
    ///                 - The lot has not concluded
    ///                 - The private key has already been submitted
    ///                 - The lot has been settled (cancelled, settled or aborted)
    ///                 - The private key is invalid for the public key
    ///
    /// @param          lotId_          The lot ID of the auction to submit the private key for
    /// @param          privateKey_     The ECIES private key to decrypt the bids
    /// @param          num_            The number of bids to decrypt after submitting the private key (passed to `_decryptAndSortBids()`)
    /// @param          sortHints_      The sort hints for the bid decryption (passed to `_decryptAndSortBids()`)
    function submitPrivateKey(
        uint96 lotId_,
        uint256 privateKey_,
        uint64 num_,
        bytes32[] calldata sortHints_
    ) external {
        // Validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotActive(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotSettled(lotId_);

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
        _decryptAndSortBids(lotId_, num_, sortHints_);
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
    ///                 - The lot has not started
    ///                 - The lot is active
    ///                 - The private key has not been provided
    ///                 - `num_` and `sortHints_` have different lengths
    ///
    /// @param          lotId_          The lot ID of the auction to decrypt bids for
    /// @param          num_            The number of bids to decrypt. Reduced to the number remaining if greater
    /// @param          sortHints_      The sort hints for the bid decryption
    function decryptAndSortBids(
        uint96 lotId_,
        uint64 num_,
        bytes32[] calldata sortHints_
    ) external {
        // Check that lotId is valid
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotActive(lotId_);

        // Revert if already decrypted or if the private key has not been provided
        if (auctionData[lotId_].status != LotStatus.Created || auctionData[lotId_].privateKey == 0)
        {
            revert Auction_WrongState(lotId_);
        }

        // Decrypt and sort bids
        _decryptAndSortBids(lotId_, num_, sortHints_);
    }

    function _decryptAndSortBids(
        uint96 lotId_,
        uint64 num_,
        bytes32[] calldata sortHints_
    ) internal {
        // Load next decrypt index and min bid size
        uint64 nextDecryptIndex = auctionData[lotId_].nextDecryptIndex;

        // Validate that the sort hints are the correct length
        if (sortHints_.length != num_) revert Auction_InvalidParams();

        // Check that the number of decrypts is less than or equal to the number of bids remaining to be decrypted
        // If so, reduce to the number remaining
        uint64[] storage bidIds = auctionData[lotId_].bidIds;
        if (num_ > bidIds.length - nextDecryptIndex) {
            num_ = uint64(bidIds.length) - nextDecryptIndex;
        }

        // Calculate base scale for use in queue insertion
        // We do this once here instead of multiple times within the loop
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;

        // Iterate over the provided number of bids, decrypt them, and then store them in the sorted bid queue
        // All submitted bids will be marked as decrypted, but only those with valid values will have the minAmountOut set and be stored in the sorted bid queue
        for (uint64 i; i < num_; i++) {
            // Decrypt the bid and store the data in the queue, if applicable
            _decrypt(lotId_, bidIds[nextDecryptIndex + i], sortHints_[i], baseScale);
        }

        // Increment next decrypt index
        auctionData[lotId_].nextDecryptIndex += num_;

        // If all bids have been decrypted, set auction status to decrypted
        if (auctionData[lotId_].nextDecryptIndex == bidIds.length) {
            auctionData[lotId_].status = LotStatus.Decrypted;
        }
    }

    /// @notice     Returns the decrypted amountOut of a single bid
    /// @dev        This function does not alter the state of the contract, but provides a way to peek at the decrypted bid
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The private key has not been provided
    ///
    /// @param      lotId_      The lot ID of the auction to decrypt the bid for
    /// @param      bidId_      The bid ID to decrypt
    /// @return     amountOut   The decrypted amount out
    function decryptBid(uint96 lotId_, uint64 bidId_) public view returns (uint256 amountOut) {
        // Load the private key
        uint256 privateKey = auctionData[lotId_].privateKey;

        // Revert if the private key has not been provided
        if (privateKey == 0) revert Auction_WrongState(lotId_);

        // Decrypt the message
        // We expect a salt calculated as the keccak256 hash of lot id, bidder, and amount to provide some (not total) uniqueness to the encryption, even if the same shared secret is used
        Bid storage bidData = bids[lotId_][bidId_];
        uint256 message = ECIES.decrypt(
            encryptedBids[lotId_][bidId_].encryptedAmountOut,
            encryptedBids[lotId_][bidId_].bidPubKey,
            privateKey,
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

        // We want to allow underflow here prior to casting to uint256
        unchecked {
            amountOut = uint256(maskedValue + seed);
        }
    }

    /// @notice     Decrypts a bid and stores it in the sorted bid queue
    function _decrypt(
        uint96 lotId_,
        uint64 bidId_,
        bytes32 sortHint_,
        uint256 baseScale_
    ) internal {
        // Decrypt the message
        Bid storage bidData = bids[lotId_][bidId_];
        uint256 plaintext = decryptBid(lotId_, bidId_);

        uint96 amountOut;
        // Only set the amount out if it is less than or equal to the maximum value of a uint96
        if (plaintext <= type(uint96).max) {
            amountOut = uint96(plaintext);
        }

        // Set bid status to decrypted
        bidData.status = BidStatus.Decrypted;

        // Only store the decrypt if the amount out is greater than or equal to zero (meaning the amount out was in range)
        // The size of the bid is checked against a minimum bid size in quote tokens on submission
        if (amountOut > 0) {
            // Only store the decrypt if the price does not overflow and is at least the minimum price
            // We don't need to check for a zero bid price, because the smallest possible bid price is 1, due to the use of mulDivUp
            // 1 * 10^6 / type(uint96).max = 1
            uint256 price = Math.mulDivUp(
                uint256(bidData.amount), 10 ** lotData[lotId_].baseTokenDecimals, uint256(amountOut)
            );
            if (price < type(uint96).max && price >= uint256(auctionData[lotId_].minPrice)) {
                // Store the decrypt in the sorted bid queue and set the min amount out on the bid
                decryptedBids[lotId_].insert(
                    sortHint_, bidId_, bidData.amount, amountOut, baseScale_
                );
                bidData.minAmountOut = amountOut; // Only set when the bid is valid. Bids below min price will have minAmountOut = 0, which means they'll just claim a refund
            }
        }

        // Emit event
        emit BidDecrypted(lotId_, bidId_, bidData.amount, amountOut);
    }

    /// @notice     Returns the bid after `key_` in the queue
    function getNextInQueue(uint96 lotId_, bytes32 key_) external view returns (bytes32) {
        return decryptedBids[lotId_].getNext(key_);
    }

    /// @notice     Returns the bid id at the specified index
    function getBidIdAtIndex(uint96 lotId_, uint256 index_) external view returns (uint64) {
        return auctionData[lotId_].bidIds[index_];
    }

    function getNumBidsInQueue(uint96 lotId_) external view returns (uint256) {
        return decryptedBids[lotId_].getNumBids();
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
    ) internal returns (uint64 bidId, uint256 amountIn, uint256 price) {
        // Load bid info (in quote token units)
        uint96 minAmountOut;
        (bidId, amountIn, minAmountOut) = queue_.delMax();

        // A zero minAmountOut value should be filtered out during decryption. However, cover the case here to avoid a potential division by zero error that would brick settlement.
        if (minAmountOut == 0) {
            // A zero price would be filtered out being below the minimum price
            return (bidId, amountIn, 0);
        }

        // Calculate the price of the bid
        price = Math.mulDivUp(amountIn, baseScale_, uint256(minAmountOut));

        return (bidId, amountIn, price);
    }

    /// @notice     Calculates the marginal price of a lot
    ///
    /// @param      lotId_          The lot ID of the auction to calculate the marginal price for
    /// @return     result          The result of the marginal price calculation
    function _getLotMarginalPrice(
        uint96 lotId_,
        uint256 num_
    ) internal returns (MarginalPriceResult memory result) {
        // Cache values used in the loop
        // Capacity is always in base token units for this auction type
        uint256 capacity = lotData[lotId_].capacity;
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        AuctionData memory lotAuctionData = auctionData[lotId_];

        // Iterate over bid queue (sorted in descending price) to calculate the marginal clearing price of the auction
        {
            uint256 lastPrice = _lotPartialSettlement[lotId_].lastPrice;
            // Initialize mandatory values in result
            result.totalAmountIn = _lotPartialSettlement[lotId_].processedAmountIn;
            result.capacityExpended = lastPrice == 0
                ? 0
                : Math.fullMulDiv(_lotPartialSettlement[lotId_].processedAmountIn, baseScale, lastPrice);

            Queue storage queue = decryptedBids[lotId_];

            uint64 lastBidId = _lotPartialSettlement[lotId_].lastBidId;
            uint256 numBids = queue.getNumBids();
            if (numBids == 0) {
                // If there are no bids, then we return early
                // This shouldn't be encountered unless there are truly zero bids in the auction
                result.finished = true;
                return result;
            }
            bool last = numBids <= num_;
            numBids = numBids > num_ ? num_ : numBids;
            for (uint256 i = 0; i < numBids; i++) {
                // A bid can be considered if:
                // - the bid price is greater than or equal to the minimum
                // - previous bids did not fill the capacity
                //
                // There is no need to check if the bid is the minimum bid size, as this was checked during decryption

                // Get bid info
                (uint64 bidId, uint256 amountIn, uint256 price) = _getNextBid(queue, baseScale);

                // Set the last bid id processed for use in the next settle call (if needed)
                result.lastBidId = bidId;

                // Check if the auction can clear with the existing bids at a price between current price and last price
                // There will be no partial fills because we select the price that exactly fills the capacity
                // Note: totalAmountIn here has not had the current bid added to it
                result.capacityExpended = Math.fullMulDiv(result.totalAmountIn, baseScale, price);
                if (result.capacityExpended >= capacity) {
                    result.marginalPrice =
                        Math.fullMulDivUp(result.totalAmountIn, baseScale, capacity);

                    // If the marginal price is re-calculated and is the same as the previous, we need to set the marginal bid id, otherwise the previous bid will not be able to claim.
                    // This only happens due to rounding. Generally, the auction would settle on the previous loop if this case is true.
                    if (lastPrice == result.marginalPrice) {
                        result.marginalBidId = lastBidId;
                    } else {
                        result.marginalBidId = uint64(0); // we set this to zero so that any bids at the current price are not considered in the case that capacityExpended == capacity
                    }

                    // Calculate the capacity expended in the same way as before, instead of setting it to `capacity`
                    // This will normally equal `capacity`, except when rounding would cause the the capacity expended to be slightly less than `capacity`
                    result.capacityExpended =
                        Math.fullMulDiv(result.totalAmountIn, baseScale, result.marginalPrice); // updated based on the marginal price
                    result.finished = true;
                    break;
                }

                // The current price will now be considered, so we can set this
                lastPrice = price;
                lastBidId = bidId;

                // Increment total amount in
                result.totalAmountIn += amountIn;

                // Determine total capacity expended at this price (in base token units)
                // quote scale * base scale / quote scale = base scale
                result.capacityExpended = Math.fullMulDiv(result.totalAmountIn, baseScale, price);

                // If total capacity expended is greater than or equal to the capacity, we have found the marginal price
                // If capacity expended is strictly greater than capacity, then we have a partially filled bid
                if (result.capacityExpended >= capacity) {
                    result.marginalPrice = price;
                    result.marginalBidId = bidId;
                    result.finished = true;
                    break;
                }

                // If we have reached the end of the queue, we check the same cases as when the price of a bid is below the minimum price.
                if (i == numBids - 1 && last) {
                    // We know that the price was not sufficient to fill capacity or the loop would have exited
                    // We check if minimum price can result in a complete fill. If so, find the exact marginal price between last price and minimum price
                    // If not, we set the marginal price to the minimum price. Whether the capacity filled meets the minimum filled will be checked later in the settlement process
                    if (
                        lotAuctionData.minPrice == 0
                            || Math.mulDiv(result.totalAmountIn, baseScale, lotAuctionData.minPrice)
                                >= capacity
                    ) {
                        result.marginalPrice =
                            Math.mulDivUp(result.totalAmountIn, baseScale, capacity);
                    } else {
                        result.marginalPrice = lotAuctionData.minPrice;
                    }

                    // If the marginal price is re-calculated and is the same as the previous, we need to set the marginal bid id, otherwise the current bid will not be able to claim.
                    if (price == result.marginalPrice) {
                        result.marginalBidId = bidId;
                    }

                    result.capacityExpended =
                        Math.fullMulDiv(result.totalAmountIn, baseScale, result.marginalPrice);
                    // marginal bid id can be zero, there are no bids at the marginal price
                    result.finished = true;
                }
            }
        }

        return result;
    }

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Iterates over the decrypted bids to calculate the marginal price and number of winning bids
    ///             - If applicable, calculates the payout and refund for a partially filled bid
    ///             - Sets the auction status to settled
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
    function _settle(
        uint96 lotId_,
        uint256 num_
    )
        internal
        override
        returns (uint256 totalIn_, uint256 totalOut_, bool, bytes memory auctionOutput_)
    {
        // Check that auction is in the right state for settlement
        if (auctionData[lotId_].status != LotStatus.Decrypted) {
            revert Auction_WrongState(lotId_);
        }

        // Get the marginal price for the auction. It may require multiple transactions to avoid the gas limit.
        // If the calculation is complete, then the result.finished value will be true.
        MarginalPriceResult memory result = _getLotMarginalPrice(lotId_, num_);

        // Cache base scaling value
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;

        // If the settlement was not finished
        if (result.finished == false) {
            // Not all bids have been processed. Store the amount in so far, the last bid id processed, and the last price for use in the next settle call.
            _lotPartialSettlement[lotId_].processedAmountIn = result.totalAmountIn;
            _lotPartialSettlement[lotId_].lastPrice =
                Math.fullMulDivUp(result.totalAmountIn, baseScale, result.capacityExpended);
            _lotPartialSettlement[lotId_].lastBidId = result.lastBidId;

            // We don't change the auction status so it can be iteratively settled

            // totalIn and totalOut are not set since the auction has not settled yet

            return (totalIn_, totalOut_, result.finished, auctionOutput_);
        }

        // Else the marginal price has been found, settle the auction
        // Cache capacity
        // Capacity is always in base token units for this auction type
        uint256 capacity = lotData[lotId_].capacity;

        // Determine if the auction can be filled, if so settle the auction, otherwise refund the seller
        // We set the status as settled either way to denote this function has been executed
        auctionData[lotId_].status = LotStatus.Settled;

        // Auction cannot be settled if the total filled is less than the minimum filled
        // or if the marginal price is less than the minimum price
        if (
            result.capacityExpended < auctionData[lotId_].minFilled
                || result.marginalPrice < auctionData[lotId_].minPrice
        ) {
            // Auction cannot be settled if we reach this point
            // Marginal price is set as the max uint256 for the auction so the system knows all bids should be refunded
            auctionData[lotId_].marginalPrice = type(uint256).max;

            // totalIn and totalOut are not set since the auction does not clear

            return (totalIn_, totalOut_, result.finished, auctionOutput_);
        }

        // Auction can be settled at the marginal price if we reach this point
        auctionData[lotId_].marginalPrice = result.marginalPrice;
        auctionData[lotId_].marginalBidId = result.marginalBidId;

        // If capacity expended is greater than capacity, then the marginal bid is partially filled
        // Set refund and payout for the bid so it can be handled during claim
        if (result.capacityExpended > capacity) {
            // Load routing and bid data
            Bid storage bidData = bids[lotId_][result.marginalBidId];

            // Calculate the payout and refund amounts
            uint256 fullFill = Math.mulDiv(uint256(bidData.amount), baseScale, result.marginalPrice);
            uint256 excess = result.capacityExpended - capacity;

            // Store the settlement data for use with partial fills
            // refund casting logic:
            // bidData.amount is a uint96.
            // excess must be less than fullFill because some of the
            // bid's capacity must be filled at the marginal price.
            // Therefore, bidData.amount * excess / fullFill < bidData.amount < 2^96
            // Using a uint96 for refund saves a storage slot since it can be
            // packed with the bid ID in the PartialFill struct.
            PartialFill memory pf = PartialFill({
                bidId: result.marginalBidId,
                refund: uint96(Math.mulDiv(uint256(bidData.amount), excess, fullFill)),
                payout: fullFill - excess
            });
            _lotPartialFill[lotId_] = pf;

            // Reduce the total amount in by the refund amount
            result.totalAmountIn -= pf.refund;
        }

        // Set settlement data
        totalIn_ = result.totalAmountIn;
        totalOut_ = result.capacityExpended > capacity ? capacity : result.capacityExpended;

        return (totalIn_, totalOut_, result.finished, auctionOutput_);
    }

    /// @inheritdoc BatchAuctionModule
    /// @dev        This function performs the following:
    ///             - Validates state
    ///             - Sets the lot status to Settled
    ///             - Sets the marginal price to the maximum value
    ///
    ///             This function assumes:
    ///             - The lot ID has been validated
    ///             - The auction is not settled
    ///
    ///             This function reverts if:
    ///             - The dedicated settle period has not passed
    function _abort(uint96 lotId_) internal override {
        // Validate that the dedicated settle period has passed
        _revertIfDedicatedSettlePeriod(lotId_);

        // Set the auction status to settled
        auctionData[lotId_].status = LotStatus.Settled;

        // Set the marginal price to the maximum value, so that all bids will be refunded
        auctionData[lotId_].marginalPrice = type(uint256).max;
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

    function getPartialFill(uint96 lotId_) external view returns (PartialFill memory) {
        _revertIfLotInvalid(lotId_);
        _revertIfLotNotSettled(lotId_);

        return _lotPartialFill[lotId_];
    }

    function getNumBids(uint96 lotId_) external view override returns (uint256) {
        _revertIfLotInvalid(lotId_);

        return auctionData[lotId_].bidIds.length;
    }

    function getBidIds(
        uint96 lotId_,
        uint256 startIndex_,
        uint256 num_
    ) external view override returns (uint64[] memory) {
        _revertIfLotInvalid(lotId_);

        uint64[] storage bidIds = auctionData[lotId_].bidIds;
        uint256 len = bidIds.length;

        // Validate that start index is within bounds
        if (startIndex_ >= len) revert Auction_InvalidParams();

        // Calculate the number of bids to return
        // Return the max of the number of bids remaining from the start index or the requested number
        // This makes it easier to iterate over without needing to specify the number of bids remaining
        uint256 remaining = len - startIndex_;
        uint256 num = num_ > remaining ? remaining : num_;

        // Initialize the array to return
        uint64[] memory result = new uint64[](num);

        // Load the bid IDs
        for (uint256 i; i < num; i++) {
            result[i] = bidIds[startIndex_ + i];
        }

        return result;
    }

    // ========== ADMIN CONFIGURATION ========== //

    function setDedicatedSettlePeriod(uint48 period_) external onlyParent {
        // Dedicated settle period cannot be more than 7 days
        if (period_ > 7 days) revert Auction_InvalidParams();

        dedicatedSettlePeriod = period_;
    }

    // ========== VALIDATION ========== //

    /// @inheritdoc AuctionModule
    function _revertIfLotActive(uint96 lotId_) internal view override {
        if (
            auctionData[lotId_].status == LotStatus.Created
                && lotData[lotId_].start <= block.timestamp
                && lotData[lotId_].conclusion > block.timestamp
        ) revert Auction_WrongState(lotId_);
    }

    function _revertIfKeySubmitted(uint96 lotId_) internal view {
        // Private key must not have been submitted yet
        if (auctionData[lotId_].privateKey != 0) {
            revert Auction_WrongState(lotId_);
        }
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfLotSettled(uint96 lotId_) internal view override {
        // Auction must not be settled
        if (auctionData[lotId_].status == LotStatus.Settled) {
            revert Auction_WrongState(lotId_);
        }
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfLotNotSettled(uint96 lotId_) internal view override {
        // Auction must be settled
        if (auctionData[lotId_].status != LotStatus.Settled) {
            revert Auction_WrongState(lotId_);
        }
    }

    function _revertIfDedicatedSettlePeriod(uint96 lotId_) internal view {
        // Auction must not be in the dedicated settle period
        uint48 conclusion = lotData[lotId_].conclusion;
        if (
            uint48(block.timestamp) >= conclusion
                && uint48(block.timestamp) < conclusion + dedicatedSettlePeriod
        ) {
            revert Auction_WrongState(lotId_);
        }
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfBidInvalid(uint96 lotId_, uint64 bidId_) internal view override {
        // Bid ID must be less than number of bids for lot
        if (bidId_ >= auctionData[lotId_].nextBidId) revert Auction_InvalidBidId(lotId_, bidId_);

        // Bid should have a bidder
        if (bids[lotId_][bidId_].bidder == address(0)) revert Auction_InvalidBidId(lotId_, bidId_);
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) internal view override {
        // Check that sender is the bidder
        if (caller_ != bids[lotId_][bidId_].bidder) revert NotPermitted(caller_);
    }

    /// @inheritdoc BatchAuctionModule
    function _revertIfBidClaimed(uint96 lotId_, uint64 bidId_) internal view override {
        // Bid must not be refunded or claimed (same status)
        if (bids[lotId_][bidId_].status == BidStatus.Claimed) {
            revert Bid_WrongState(lotId_, bidId_);
        }
    }
}
