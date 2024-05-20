// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IBatchAuction} from "src/interfaces/modules/IBatchAuction.sol";
import {IEncryptedDerivativeValue} from
    "src/interfaces/modules/auctions/IEncryptedDerivativeValue.sol";

// Internal libraries
import {ECIES, Point} from "src/lib/ECIES.sol";
import {PriorityQueue, Queue} from "src/modules/auctions/batch/EDV/PriorityQueue.sol";

// External libraries
import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";

// Auctions
import {AuctionModule} from "src/modules/Auction.sol";
import {BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";

import {Module, Veecode, toVeecode} from "src/modules/Modules.sol";

/// @notice     Encrypted Derivative Value
/// @dev
///
///             Note the max derivative value is bound by the max uint192 value
contract EncryptedDerivativeValue is BatchAuctionModule, IEncryptedDerivativeValue {
    using PriorityQueue for Queue;

    // ========== DATA STRUCTURES ========== //

    /// @notice Stuct containing the marginal price result
    /// @dev    Memory only, no need to pack
    ///
    /// @param  marginalValue       The marginal derivative value of the auction. Set only if the marginal value has been determined.
    /// @param  marginalBidId       The ID of the marginal bid (marking that bids following it are not filled). Set only if the marginal price has been determined and there is a need for this to be set.
    /// @param  totalAmountIn       The total amount in from bids processed so far. This should always be set, regardless of the settlement outcome.
    /// @param  capacityExpended    The total capacity expended from bids processed so far. This should always be set, regardless of the settlement outcome.
    /// @param  finished            Whether settlement has been completed.
    struct MarginalValueResult {
        uint128 marginalValue;
        uint64 marginalBidId;
        uint256 totalAmountIn;
        uint256 capacityExpended;
        bool finished;
    }

    /// @notice Struct to store the data for in-progress settlement
    ///
    /// @param  processedAmountIn   The total amount in from bids processed so far (during settlement)
    struct PartialSettlement {
        uint256 processedAmountIn;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     Auction-specific data for a lot
    /// @dev        Access via `getAuctionData()`
    mapping(uint96 lotId => AuctionData) public auctionData;

    /// @notice     Partial fill data for a lot
    /// @dev        Each EMPA can have at most one partial fill
    ///             Access via `getPartialFill()`
    mapping(uint96 lotId => PartialFill) internal _lotPartialFill;

    /// @notice     Partial settlement data stored between settlement batches
    /// @dev        Only used internally, does not need a public accessor
    mapping(uint96 lotId => PartialSettlement) internal _lotPartialSettlement;

    /// @notice     General information about bids on a lot
    /// @dev        Access via `getBid()`
    mapping(uint96 lotId => mapping(uint64 bidId => Bid)) public bids;

    /// @notice     Data for encryption information for a specific bid
    /// @dev        Access via `getBid()`
    mapping(uint96 lotId => mapping(uint64 bidId => EncryptedBid)) public encryptedBids; // each encrypted amount is 4 slots (length + 3 slots)

    /// @notice     Queue of decrypted bids for a lot (populated on decryption)
    /// @dev        Access elements via `getNextInQueue()`
    mapping(uint96 lotId => Queue) public decryptedBids;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day initially
        minAuctionDuration = 1 days;

        // Set the dedicated settle period to 1 day initially
        dedicatedSettlePeriod = 1 days;
    }

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01EDVA");
    }

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
    ///
    /// @param      params_    ABI-encoded data of type `IEncryptedDerivativeValue.AuctionDataParams`
    function _auction(uint96 lotId_, Lot memory lot_, bytes memory params_) internal override {
        // Decode implementation params
        AuctionDataParams memory implParams = abi.decode(params_, (AuctionDataParams));

        // Validate params

        // price must not be zero
        if (implParams.price == 0) revert Auction_InvalidParams();

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
        data.minValue = implParams.minValue;
        data.price = implParams.price;
        // We round up to be conservative with the minimums
        data.minFilled =
            Math.fullMulDivUp(lot_.capacity, implParams.minFillPercent, _ONE_HUNDRED_PERCENT);
        data.minBidSize = implParams.minBidSize;
        data.publicKey = implParams.publicKey;
        data.nextBidId = 1;

        decryptedBids[lotId_].initialize(implParams.sortHighToLow);
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
    ///
    /// @param      auctionData_    ABI-encoded data of type `IEncryptedDerivativeValue.BidParams`
    function _bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint64 bidId) {
        // Decode auction data
        (uint256 encryptedDerivativeValue, Point memory bidPubKey) =
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

        // Store encrypted derivative value and bid public key
        encryptedBids[lotId_][bidId] = EncryptedBid(encryptedDerivativeValue, bidPubKey);

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
    ///             - The bid has not been refunded
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

        // Get the BidClaim
        bidClaim = _getBidClaim(lotId_, bidId_);

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
    ///             - The auction has concluded
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

    /// @inheritdoc IEncryptedDerivativeValue
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
    ///             - The lot is not active
    ///             - The lot has not concluded
    ///             - The private key has already been submitted
    ///             - The lot has been settled (cancelled, settled or aborted)
    ///             - The private key is invalid for the public key
    function submitPrivateKey(
        uint96 lotId_,
        uint256 privateKey_,
        uint64 num_,
        bytes32[] calldata sortHints_
    ) external override {
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

    /// @inheritdoc IEncryptedDerivativeValue
    /// @dev        This function handles the following:
    ///             - Performs state validation
    ///             - Iterates over the encrypted bids:
    ///                 - Decrypts the bid
    ///                 - Ignores if the bid is incorrectly encrypted
    ///                 - Does not add to the sorted bid queue if the decrypted amount out is less than the minimum bid size or overflows
    ///                 - Otherwise, adds to the sorted bid queue for use during settlement
    ///             - Determines the next decrypt index
    ///             - Sets the auction status to decrypted if all bids have been decrypted
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The lot has not started
    ///             - The lot is active
    ///             - The private key has not been provided
    ///             - `num_` and `sortHints_` have different lengths
    function decryptAndSortBids(
        uint96 lotId_,
        uint64 num_,
        bytes32[] calldata sortHints_
    ) external override {
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

        // Cache the sort order of the lot
        bool highToLow = sortHighToLow(lotId_);

        // Iterate over the provided number of bids, decrypt them, and then store them in the sorted bid queue
        // All submitted bids will be marked as decrypted, but only those with valid values will have the minAmountOut set and be stored in the sorted bid queue
        for (uint64 i; i < num_; i++) {
            // Decrypt the bid and store the data in the queue, if applicable
            _decrypt(lotId_, bidIds[nextDecryptIndex + i], sortHints_[i], highToLow);
        }

        // Increment next decrypt index
        auctionData[lotId_].nextDecryptIndex += num_;

        // If all bids have been decrypted, set auction status to decrypted
        if (auctionData[lotId_].nextDecryptIndex == bidIds.length) {
            auctionData[lotId_].status = LotStatus.Decrypted;
        }
    }

    /// @inheritdoc IEncryptedDerivativeValue
    /// @dev        This function does not alter the state of the contract, but provides a way to peek at the decrypted bid
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The private key has not been provided
    function decryptBid(
        uint96 lotId_,
        uint64 bidId_
    ) public view override returns (uint128 derivativeValue) {
        // Load the private key
        uint256 privateKey = auctionData[lotId_].privateKey;

        // Revert if the private key has not been provided
        if (privateKey == 0) revert Auction_WrongState(lotId_);

        // Decrypt the message
        // We expect a salt calculated as the keccak256 hash of lot id, bidder, and amount to provide some (not total) uniqueness to the encryption, even if the same shared secret is used
        Bid storage bidData = bids[lotId_][bidId_];
        uint256 message = ECIES.decrypt(
            encryptedBids[lotId_][bidId_].encryptedDerivativeValue,
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

        // We want to allow overflow here to remove the seed from the masked value
        unchecked {
            derivativeValue = maskedValue + seed;
        }
    }

    /// @notice     Decrypts a bid and stores it in the sorted bid queue
    function _decrypt(uint96 lotId_, uint64 bidId_, bytes32 sortHint_, bool highToLow_) internal {
        // Decrypt the message
        Bid storage bidData = bids[lotId_][bidId_];
        uint128 derivativeValue = decryptBid(lotId_, bidId_);

        // Set bid status to decrypted
        bidData.status = BidStatus.Decrypted;

        // Only store the decrypt if the derivative value is greater than or equal to the minimum value
        if (derivativeValue >= auctionData[lotId_].minValue) {
            // Store the decrypt in the sorted bid queue and set the min amount out on the bid
            decryptedBids[lotId_].insert(sortHint_, bidId_, derivativeValue);
            bidData.derivativeValue = derivativeValue;
        } else {
            // If the derivative value is less than the minimum value,
            // set the derivative value to either 0 (high to low) or max uint128 (low to high)
            bidData.derivativeValue = highToLow_ ? 0 : type(uint128).max;
        }

        // Emit event
        emit BidDecrypted(lotId_, bidId_, derivativeValue);
    }

    /// @inheritdoc IEncryptedDerivativeValue
    function getNextInQueue(uint96 lotId_, bytes32 key_) external view override returns (bytes32) {
        return decryptedBids[lotId_].getNext(key_);
    }

    /// @inheritdoc IEncryptedDerivativeValue
    function getNumBidsInQueue(uint96 lotId_) external view override returns (uint256) {
        return decryptedBids[lotId_].getNumBids();
    }

    /// @inheritdoc IEncryptedDerivativeValue
    function sortHighToLow(uint96 lotId_) public view override returns (bool) {
        return decryptedBids[lotId_].isMaxPriorityQueue;
    }

    // ========== SETTLEMENT ========== //

    /// @notice     Calculates the marginal price of a lot
    ///
    /// @param      lotId_          The lot ID of the auction to calculate the marginal price for
    /// @return     result          The result of the marginal price calculation
    function _getLotMarginalValue(
        uint96 lotId_,
        uint256 num_
    ) internal returns (MarginalValueResult memory result) {
        // Cache values used in the loop
        // Capacity is always in base token units for this auction type
        uint256 capacity = lotData[lotId_].capacity;
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        AuctionData memory lotAuctionData = auctionData[lotId_];

        // Iterate over bid queue to calculate the marginal derivative value of the auction
        {
            // Initialize mandatory values in result
            result.totalAmountIn = _lotPartialSettlement[lotId_].processedAmountIn;
            result.capacityExpended =
                Math.fullMulDiv(result.totalAmountIn, baseScale, lotAuctionData.price);

            // Load the queue
            Queue storage queue = decryptedBids[lotId_];

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
                // - the bid value is greater than or equal to the minimum
                // - previous bids did not fill the capacity
                //
                // There is no need to check if the bid is the minimum bid size, as this was checked during decryption

                // Get bid info
                (uint64 bidId, uint128 value) = queue.delMax();

                // Load the bid amount
                uint256 amountIn = bids[lotId_][bidId].amount;

                // Increment total amount in
                result.totalAmountIn += amountIn;

                // Determine total capacity expended including this bid
                // quote scale * base scale / quote scale = base scale
                result.capacityExpended =
                    Math.fullMulDiv(result.totalAmountIn, baseScale, lotAuctionData.price);

                // If total capacity expended is greater than or equal to the capacity, we have found the marginal price
                // If capacity expended is strictly greater than capacity, then we have a partially filled bid
                if (result.capacityExpended >= capacity) {
                    result.marginalValue = value;
                    result.marginalBidId = bidId;
                    result.finished = true;
                    break;
                }

                // If we have reached the end of the queue, we return the minimum value as the marginal bid value since the capacity did not fill completely with all valid bids
                // Whether the capacity expended meets the minimum fill threshold is checked in the settle function
                if (i == numBids - 1 && last) {
                    result.marginalValue = lotAuctionData.minValue;

                    // If the last bid value is the minimum value, then the marginal bid is the last bid
                    // Otherwise, we don't need to set it since all valid bids will be greater than the minimum value
                    if (value == lotAuctionData.minValue) {
                        result.marginalBidId = bidId;
                    }

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

        // Get the marginal value for the auction. It may require multiple transactions to avoid the gas limit.
        // If the calculation is complete, then the result.finished value will be true.
        MarginalValueResult memory result = _getLotMarginalValue(lotId_, num_);

        // Cache base scaling value
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;

        // If the settlement was not finished
        if (result.finished == false) {
            // Not all bids have been processed. Store the amount in so far for use in the next settle call.
            _lotPartialSettlement[lotId_].processedAmountIn = result.totalAmountIn;

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
        // or if the marginal value is less than the minimum value
        if (
            result.capacityExpended < auctionData[lotId_].minFilled
                || result.marginalValue < auctionData[lotId_].minValue
        ) {
            // Auction cannot be settled if we reach this point
            // Marginal value is set as the max uint128 for the auction so the system knows all bids should be refunded
            auctionData[lotId_].marginalValue = type(uint128).max;

            // totalIn and totalOut are not set since the auction does not clear

            return (totalIn_, totalOut_, result.finished, auctionOutput_);
        }

        // Auction can be settled at the marginal value if we reach this point
        auctionData[lotId_].marginalValue = result.marginalValue;
        auctionData[lotId_].marginalBidId = result.marginalBidId;

        // If capacity expended is greater than capacity, then the marginal bid is partially filled
        // Set refund and payout for the bid so it can be handled during claim
        if (result.capacityExpended > capacity) {
            // Load routing and bid data
            Bid storage bidData = bids[lotId_][result.marginalBidId];

            // Calculate the payout and refund amounts
            uint256 fullFill =
                Math.mulDiv(uint256(bidData.amount), baseScale, auctionData[lotId_].price);
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
    ///             - The dedicated settle period has not passed
    ///
    ///             This function reverts if:
    ///             - None
    function _abort(uint96 lotId_) internal override {
        // Set the auction status to settled
        auctionData[lotId_].status = LotStatus.Settled;

        // Set the marginal value to the max uint128, so that all bids will be refunded
        auctionData[lotId_].marginalValue = type(uint128).max;
    }

    // ========== AUCTION INFORMATION ========== //

    /// @inheritdoc IEncryptedDerivativeValue
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
    ///             - The bid ID is invalid
    function getBid(
        uint96 lotId_,
        uint64 bidId_
    ) external view returns (Bid memory bid, EncryptedBid memory encryptedBid) {
        _revertIfLotInvalid(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);

        return (bids[lotId_][bidId_], encryptedBids[lotId_][bidId_]);
    }

    /// @inheritdoc IEncryptedDerivativeValue
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
    function getAuctionData(uint96 lotId_)
        external
        view
        override
        returns (AuctionData memory auctionData_)
    {
        _revertIfLotInvalid(lotId_);

        return auctionData[lotId_];
    }

    /// @inheritdoc IEncryptedDerivativeValue
    /// @dev        For ease of use, this function determines if a partial fill exists.
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The lot is not settled
    function getPartialFill(uint96 lotId_)
        external
        view
        returns (bool hasPartialFill, PartialFill memory partialFill)
    {
        _revertIfLotInvalid(lotId_);
        _revertIfLotNotSettled(lotId_);

        partialFill = _lotPartialFill[lotId_];
        hasPartialFill = partialFill.bidId != 0;

        return (hasPartialFill, partialFill);
    }

    /// @inheritdoc IBatchAuction
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
    function getNumBids(uint96 lotId_) external view override returns (uint256) {
        _revertIfLotInvalid(lotId_);

        return auctionData[lotId_].bidIds.length;
    }

    /// @inheritdoc IBatchAuction
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
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

    /// @notice Returns the `BidClaim` data for a given lot and bid ID
    /// @dev    This function assumes:
    ///         - The lot ID has been validated
    ///         - The bid ID has been validated
    ///
    /// @param  lotId_          The lot ID
    /// @param  bidId_          The bid ID
    /// @return bidClaim        The `BidClaim` data
    function _getBidClaim(
        uint96 lotId_,
        uint64 bidId_
    ) internal view returns (BidClaim memory bidClaim) {
        // Load bid data
        Bid memory bidData = bids[lotId_][bidId_];

        // Load the bidder and referrer addresses
        bidClaim.bidder = bidData.bidder;
        bidClaim.referrer = bidData.referrer;

        // Calculate the bid
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        uint128 value = bidData.derivativeValue;
        uint128 marginalValue = auctionData[lotId_].marginalValue;
        bool highValueBest = sortHighToLow(lotId_);

        // If the bidId matches the partial fill for the lot, assign the stored data.
        // Otherwise,
        // If the auctions is sorting bids from highest to lowest and bid value is greater than the marginal value, the bid is filled.
        // If the auctions is sorting bids from lowest to highest and bid value is less than the marginal value, the bid is filled.
        // If the bid value is equal to the marginal value and the bid was submitted before or is the marginal bid, the bid is filled.
        // Auctions that do not meet capacity or min value thresholds to settle will have their marginal value set at the max uint128
        // and there will be no partial fill. Therefore, all bids will be refunded.
        if (_lotPartialFill[lotId_].bidId == bidId_) {
            bidClaim.paid = bidData.amount;
            bidClaim.payout = _lotPartialFill[lotId_].payout;
            bidClaim.refund = _lotPartialFill[lotId_].refund;
        } else if (
            (highValueBest && value > marginalValue) || (!highValueBest && value < marginalValue)
                || (value == marginalValue && bidId_ <= auctionData[lotId_].marginalBidId)
        ) {
            // Payout is calculated using the marginal price of the auction
            bidClaim.paid = bidData.amount;
            bidClaim.payout = Math.mulDiv(bidClaim.paid, baseScale, auctionData[lotId_].price);
        } else {
            // Bidder is refunded the paid amount and receives no payout
            bidClaim.paid = bidData.amount;
            bidClaim.refund = bidData.amount;
        }

        return bidClaim;
    }

    /// @inheritdoc IBatchAuction
    function getBidIdAtIndex(
        uint96 lotId_,
        uint256 index_
    ) external view override returns (uint64) {
        return auctionData[lotId_].bidIds[index_];
    }

    /// @inheritdoc IBatchAuction
    /// @dev        This function reverts if:
    ///             - The lot ID is invalid
    ///             - The lot is not settled (since there would be no claim)
    ///             - The bid ID is invalid
    function getBidClaim(
        uint96 lotId_,
        uint64 bidId_
    ) external view override returns (BidClaim memory bidClaim) {
        _revertIfLotInvalid(lotId_);
        _revertIfLotNotSettled(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);

        return _getBidClaim(lotId_, bidId_);
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

    /// @notice Reverts if the private key has been submitted for the lot
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
