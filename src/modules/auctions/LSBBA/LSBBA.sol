/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {AuctionModule} from "src/modules/Auction.sol";
import {Veecode, toVeecode} from "src/modules/Modules.sol";
import {RSAOAEP} from "src/lib/RSA.sol";
import {MinPriorityQueue, Bid as QueueBid} from "src/modules/auctions/LSBBA/MinPriorityQueue.sol";

// A completely on-chain sealed bid batch auction that uses RSA encryption to hide bids until after the auction ends
// The auction occurs in three phases:
// 1. Bidding - bidders submit encrypted bids
// 2. Decryption - anyone with the private key can decrypt bids off-chain and submit them on-chain for validation and sorting
// 3. Settlement - once all bids are decryped, the auction can be settled and proceeds transferred
contract LocalSealedBidBatchAuction is AuctionModule {
    using MinPriorityQueue for MinPriorityQueue.Queue;

    // ========== ERRORS ========== //
    error Auction_BidDoesNotExist();
    error Auction_AlreadyCancelled();
    error Auction_WrongState();
    error Auction_NotLive();
    error Auction_NotConcluded();
    error Auction_InvalidDecrypt();

    // ========== DATA STRUCTURES ========== //

    enum AuctionStatus {
        Created,
        Decrypted,
        Settled
    }

    enum BidStatus {
        Submitted,
        Cancelled,
        Decrypted,
        Won,
        Refunded
    }

    struct EncryptedBid {
        BidStatus status;
        address bidder;
        address recipient;
        address referrer;
        uint256 amount;
        bytes encryptedAmountOut;
    }

    struct Decrypt {
        uint256 amountOut;
        uint256 seed;
    }

    struct AuctionData {
        AuctionStatus status;
        uint96 nextDecryptIndex;
        uint256 minimumPrice;
        uint256 minFilled; // minimum amount of capacity that must be filled to settle the auction
        uint256 minBidSize; // minimum amount that can be bid for the lot, determined by the percentage of capacity that must be filled per bid times the min bid price
        bytes publicKeyModulus;
    }

    /// @notice         Struct containing parameters for creating a new LSBBA auction
    ///
    /// @param          minFillPercent_     The minimum percentage of the lot capacity that must be filled for the auction to settle (_SCALE: `_ONE_HUNDRED_PERCENT`)
    /// @param          minBidPercent_      The minimum percentage of the lot capacity that must be bid for each bid (_SCALE: `_ONE_HUNDRED_PERCENT`)
    /// @param          minimumPrice_       The minimum price that the auction can settle at
    /// @param          publicKeyModulus_   The public key modulus used to encrypt bids
    struct AuctionDataParams {
        uint24 minFillPercent;
        uint24 minBidPercent;
        uint256 minimumPrice;
        bytes publicKeyModulus;
    }

    // ========== STATE VARIABLES ========== //

    uint24 internal constant _MIN_BID_PERCENT = 1000; // 1%
    uint24 internal constant _PUB_KEY_EXPONENT = 65_537; // TODO can be 3 to save gas, but 65537 is probably more secure
    uint256 internal constant _SCALE = 1e18; // TODO maybe set this per auction if decimals mess us up

    mapping(uint96 lotId => AuctionData) public auctionData;
    mapping(uint96 lotId => EncryptedBid[] bids) public lotEncryptedBids;
    mapping(uint96 lotId => MinPriorityQueue.Queue) public lotSortedBids; // TODO must create and call `initialize` on it during auction creation

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day
        // TODO is this a good default?
        minAuctionDuration = 1 days;
    }

    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01LSBBA");
    }

    function TYPE() public pure override returns (Type) {
        return Type.Auction;
    }

    // ========== MODIFIERS ========== //

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the lot is active with the data structures used by this particular module
    function _revertIfLotInactive(uint96 lotId_) internal view override {
        // Check that bids are allowed to be submitted for the lot
        if (
            auctionData[lotId_].status != AuctionStatus.Created
                || block.timestamp < lotData[lotId_].start
                || block.timestamp >= lotData[lotId_].conclusion
        ) revert Auction_NotLive();
    }

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the lot is not yet settled
    function _revertIfLotSettled(uint96 lotId_) internal view override {
        // Auction must not be settled
        if (auctionData[lotId_].status == AuctionStatus.Settled) {
            revert Auction_MarketNotActive(lotId_);
        }
    }

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the bid is valid
    function _revertIfBidInvalid(uint96 lotId_, uint256 bidId_) internal view override {
        // Bid ID must be less than number of bids for lot
        if (bidId_ >= lotEncryptedBids[lotId_].length) revert Auction_InvalidBidId(lotId_, bidId_);
    }

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the sender is the bidder
    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint256 bidId_,
        address bidder_
    ) internal view override {
        // Check that sender is the bidder
        if (bidder_ != lotEncryptedBids[lotId_][bidId_].bidder) revert Auction_NotBidder();
    }

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the bid is not already cancelled
    function _revertIfBidCancelled(uint96 lotId_, uint256 bidId_) internal view override {
        // Bid must not be cancelled
        if (lotEncryptedBids[lotId_][bidId_].status == BidStatus.Cancelled) {
            revert Auction_AlreadyCancelled();
        }
    }

    // =========== BID =========== //

    /// @inheritdoc AuctionModule
    function _bid(
        uint96 lotId_,
        address bidder_,
        address recipient_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint256 bidId) {
        // Validate inputs
        // Amount at least minimum bid size for lot
        if (amount_ < auctionData[lotId_].minBidSize) revert Auction_AmountLessThanMinimum();

        // Amount greater than capacity
        if (amount_ > lotData[lotId_].capacity) revert Auction_NotEnoughCapacity();

        // Store bid data
        // Auction data should just be the encrypted amount out (no decoding required)
        EncryptedBid memory userBid;
        userBid.bidder = bidder_;
        userBid.recipient = recipient_;
        userBid.referrer = referrer_;
        userBid.amount = amount_;
        userBid.encryptedAmountOut = auctionData_;
        userBid.status = BidStatus.Submitted;

        // Bid ID is the next index in the lot's bid array
        bidId = lotEncryptedBids[lotId_].length;

        // Add bid to lot
        lotEncryptedBids[lotId_].push(userBid);

        return bidId;
    }

    /// @inheritdoc AuctionModule
    // TODO need to change this to delete the bid so we don't have to decrypt it later
    // Because of this, we can issue the refund immediately (needs to happen in the AuctionHouse)
    // However, this will require more refactoring because, we run into a problem of using the array index as the bidId since it will change when we delete the bid
    // It doesn't cost any more gas to store a uint96 bidId as part of the EncryptedBid.
    // A better approach may be to create a mapping of lotId => bidId => EncryptedBid. Then, have an array of bidIds in the AuctionData struct that can be iterated over.
    // This way, we can still lookup the bids by bidId for cancellation, etc.
    function _cancelBid(
        uint96 lotId_,
        uint256 bidId_,
        address
    ) internal override returns (uint256 refundAmount) {
        // Validate inputs

        // Set bid status to cancelled
        lotEncryptedBids[lotId_][bidId_].status = BidStatus.Cancelled;

        // Return the amount to be refunded
        return lotEncryptedBids[lotId_][bidId_].amount;
    }

    // =========== DECRYPTION =========== //

    function decryptAndSortBids(uint96 lotId_, Decrypt[] memory decrypts_) external {
        // Check that auction is in the right state for decryption
        if (
            auctionData[lotId_].status != AuctionStatus.Created
                || block.timestamp < lotData[lotId_].conclusion
        ) revert Auction_WrongState();

        // Load next decrypt index
        uint96 nextDecryptIndex = auctionData[lotId_].nextDecryptIndex;
        uint96 len = uint96(decrypts_.length);

        // Check that the number of decrypts is less than or equal to the number of bids remaining to be decrypted
        if (len > lotEncryptedBids[lotId_].length - nextDecryptIndex) {
            revert Auction_InvalidDecrypt();
        }

        // Iterate over decrypts, validate that they match the stored encrypted bids, then store them in the sorted bid queue
        for (uint96 i; i < len; i++) {
            // Re-encrypt the decrypt to confirm that it matches the stored encrypted bid
            bytes memory ciphertext = _encrypt(lotId_, decrypts_[i]);

            // Load encrypted bid
            EncryptedBid storage encBid = lotEncryptedBids[lotId_][nextDecryptIndex + i];

            // Check that the encrypted bid matches the re-encrypted decrypt by hashing both
            if (keccak256(ciphertext) != keccak256(encBid.encryptedAmountOut)) {
                revert Auction_InvalidDecrypt();
            }

            // If the bid has been cancelled, it shouldn't be added to the queue
            // TODO should this just check != Submitted?
            if (encBid.status == BidStatus.Cancelled) continue;

            // Store the decrypt in the sorted bid queue
            lotSortedBids[lotId_].insert(
                nextDecryptIndex + i, encBid.amount, decrypts_[i].amountOut
            );

            // Set bid status to decrypted
            encBid.status = BidStatus.Decrypted;
        }

        // Increment next decrypt index
        auctionData[lotId_].nextDecryptIndex += len;

        // If all bids have been decrypted, set auction status to decrypted
        if (auctionData[lotId_].nextDecryptIndex == lotEncryptedBids[lotId_].length) {
            auctionData[lotId_].status = AuctionStatus.Decrypted;
        }
    }

    function _encrypt(
        uint96 lotId_,
        Decrypt memory decrypt_
    ) internal view returns (bytes memory) {
        return RSAOAEP.encrypt(
            abi.encodePacked(decrypt_.amountOut),
            abi.encodePacked(lotId_),
            abi.encodePacked(_PUB_KEY_EXPONENT),
            auctionData[lotId_].publicKeyModulus,
            decrypt_.seed
        );
    }

    /// @notice View function that can be used to obtain a certain number of the next bids to decrypt off-chain
    // TODO This assumes that cancelled bids have been removed, but hasn't been refactored based on the comments over `cancelBid`
    function getNextBidsToDecrypt(
        uint96 lotId_,
        uint256 number_
    ) external view returns (EncryptedBid[] memory) {
        // Load next decrypt index
        uint96 nextDecryptIndex = auctionData[lotId_].nextDecryptIndex;

        // Load number of bids to decrypt
        uint256 len = lotEncryptedBids[lotId_].length - nextDecryptIndex;
        if (number_ < len) len = number_;

        // Create array of encrypted bids
        EncryptedBid[] memory bids = new EncryptedBid[](len);

        // Iterate over bids and add them to the array
        for (uint256 i; i < len; i++) {
            bids[i] = lotEncryptedBids[lotId_][nextDecryptIndex + i];
        }

        // Return array of encrypted bids
        return bids;
    }

    // Note: we may need to remove this function due to issues with chosen plaintext attacks on RSA implementations
    // /// @notice View function that can be used to obtain the amount out and seed for a given bid by providing the private key
    // /// @dev This function can be used to decrypt bids off-chain if you know the private key
    // function decryptBid(
    //     uint96 lotId_,
    //     uint96 bidId_,
    //     bytes memory privateKey_
    // ) external view returns (Decrypt memory) {
    //     // Load encrypted bid
    //     EncryptedBid memory encBid = lotEncryptedBids[lotId_][bidId_];

    //     // Decrypt the encrypted amount out
    //     (bytes memory amountOut, bytes32 seed) = RSAOAEP.decrypt(
    //         encBid.encryptedAmountOut,
    //         abi.encodePacked(lotId_),
    //         privateKey_,
    //         auctionData[lotId_].publicKeyModulus
    //     );

    //     // Cast the decrypted values
    //     Decrypt memory decrypt;
    //     decrypt.amountOut = abi.decode(amountOut, (uint256));
    //     decrypt.seed = uint256(seed);

    //     // Return the decrypt
    //     return decrypt;
    // }

    // =========== SETTLEMENT =========== //

    /// @inheritdoc AuctionModule
    function _settle(uint96 lotId_)
        internal
        override
        returns (Bid[] memory winningBids_, bytes memory auctionOutput_)
    {
        // Check that auction is in the right state for settlement
        if (auctionData[lotId_].status != AuctionStatus.Decrypted) revert Auction_WrongState();

        // Cache capacity
        uint256 capacity = lotData[lotId_].capacity;

        // Iterate over bid queue to calculate the marginal clearing price of the auction
        MinPriorityQueue.Queue storage queue = lotSortedBids[lotId_];
        uint256 marginalPrice;
        uint256 totalAmountIn;
        uint256 winningBidIndex;
        for (uint256 i = 1; i <= queue.numBids; i++) {
            // Load bid
            QueueBid storage qBid = queue.getBid(i);

            // Calculate bid price
            uint256 price = (qBid.amountIn * _SCALE) / qBid.minAmountOut;

            // Increment total amount in
            totalAmountIn += qBid.amountIn;

            // Determine total capacity expended at this price
            uint256 expended = (totalAmountIn * _SCALE) / price;

            // If total capacity expended is greater than or equal to the capacity, we have found the marginal price
            if (expended >= capacity) {
                marginalPrice = price;
                winningBidIndex = i;
                break;
            }

            // If we have reached the end of the queue, we have found the marginal price and the maximum capacity that can be filled
            if (i == queue.numBids) {
                // If the total filled is less than the minimum filled, mark as settled and return no winning bids (so users can claim refunds)
                if (expended < auctionData[lotId_].minFilled) {
                    auctionData[lotId_].status = AuctionStatus.Settled;
                    return (winningBids_, bytes(""));
                } else {
                    marginalPrice = price;
                    winningBidIndex = i;
                }
            }
        }

        // Check if the minimum price for the auction was reached
        // If not, mark as settled and return no winning bids (so users can claim refunds)
        if (marginalPrice < auctionData[lotId_].minimumPrice) {
            auctionData[lotId_].status = AuctionStatus.Settled;
            return (winningBids_, bytes(""));
        }

        // Auction can be settled at the marginal price if we reach this point
        // Create winning bid array using marginal price to set amounts out
        winningBids_ = new Bid[](winningBidIndex);
        for (uint256 i; i < winningBidIndex; i++) {
            // Load bid
            QueueBid memory qBid = queue.delMin();

            // Calculate amount out
            // TODO handle partial filling of the last winning bid
            // amountIn, and amountOut will be lower
            // Need to somehow refund the amountIn that wasn't used to the user
            // We know it will always be the last bid in the returned array, can maybe do something with that
            uint256 amountOut = (qBid.amountIn * _SCALE) / marginalPrice;

            // Create winning bid from encrypted bid and calculated amount out
            EncryptedBid storage encBid = lotEncryptedBids[lotId_][qBid.encId];
            Bid memory winningBid;
            winningBid.bidder = encBid.bidder;
            winningBid.recipient = encBid.recipient;
            winningBid.referrer = encBid.referrer;
            winningBid.amount = encBid.amount;
            winningBid.minAmountOut = amountOut;

            // Set bid status to won
            encBid.status = BidStatus.Won;

            // Add winning bid to array
            winningBids_[i] = winningBid;
        }

        // Set auction status to settled
        auctionData[lotId_].status = AuctionStatus.Settled;

        // Return winning bids
        return (winningBids_, bytes(""));
    }

    // =========== AUCTION MANAGEMENT ========== //

    /// @inheritdoc AuctionModule
    /// @dev        Creates a new auction lot for the LSBBA auction type.
    function _auction(
        uint96 lotId_,
        Lot memory lot_,
        bytes memory params_
    ) internal override returns (bool prefundingRequired) {
        // Decode implementation params
        AuctionDataParams memory implParams = abi.decode(params_, (AuctionDataParams));

        // Validate params
        // Capacity must be in base token for this auction type
        if (lot_.capacityInQuote) revert Auction_InvalidParams();

        // minFillPercent must be less than or equal to 100%
        // TODO should there be a minimum?
        if (implParams.minFillPercent > _ONE_HUNDRED_PERCENT) revert Auction_InvalidParams();

        // minBidPercent must be greater than or equal to the global min and less than or equal to 100%
        // TODO should we cap this below 100%?
        if (
            implParams.minBidPercent < _MIN_BID_PERCENT
                || implParams.minBidPercent > _ONE_HUNDRED_PERCENT
        ) {
            revert Auction_InvalidParams();
        }

        // publicKeyModulus must be 1024 bits (128 bytes)
        if (implParams.publicKeyModulus.length != 128) revert Auction_InvalidParams();

        // Store auction data
        AuctionData storage data = auctionData[lotId_];
        data.minimumPrice = implParams.minimumPrice;
        data.minFilled = (lot_.capacity * implParams.minFillPercent) / _ONE_HUNDRED_PERCENT;
        data.minBidSize = (lot_.capacity * implParams.minBidPercent) / _ONE_HUNDRED_PERCENT;
        data.publicKeyModulus = implParams.publicKeyModulus;

        // Initialize sorted bid queue
        lotSortedBids[lotId_].initialize();

        // This auction type requires pre-funding
        return (true);
    }

    function _cancelAuction(uint96 lotId_) internal override {
        // Validation
        // Batch auctions cannot be cancelled once started, otherwise the seller could cancel the auction after bids have been submitted
        _revertIfLotActive(lotId_);

        // Auction cannot be cancelled once it has concluded
        _revertIfLotConcluded(lotId_);

        // Set auction status to settled so that bids can be refunded
        auctionData[lotId_].status = AuctionStatus.Settled;
    }

    function payoutFor(
        uint256 id_,
        uint256 amount_
    ) public view virtual override returns (uint256) {}

    function priceFor(
        uint256 id_,
        uint256 payout_
    ) public view virtual override returns (uint256) {}

    function maxPayout(uint256 id_) public view virtual override returns (uint256) {}

    function maxAmountAccepted(uint256 id_) public view virtual override returns (uint256) {}

    function getLotData(uint96 lotId_) public view returns (AuctionData memory) {
        return auctionData[lotId_];
    }

    function getBidData(uint96 lotId_, uint256 bidId_) public view returns (EncryptedBid memory) {
        return lotEncryptedBids[lotId_][bidId_];
    }

    function getSortedBidData(
        uint96 lotId_,
        uint96 index_
    ) public view returns (QueueBid memory) {
        return lotSortedBids[lotId_].getBid(index_);
    }

    function getSortedBidCount(uint96 lotId_) public view returns (uint256) {
        return lotSortedBids[lotId_].numBids;
    }

    // =========== ATOMIC AUCTION STUBS ========== //

    /// @inheritdoc AuctionModule
    /// @dev        Atomic auctions are not supported by this auction type
    function _purchase(
        uint96,
        uint256,
        bytes calldata
    ) internal pure override returns (uint256, bytes memory) {
        revert Auction_NotImplemented();
    }
}
