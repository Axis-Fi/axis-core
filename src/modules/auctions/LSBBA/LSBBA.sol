/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {AuctionModule} from "src/modules/Auction.sol";
import {Veecode, toVeecode} from "src/modules/Modules.sol";
import {RSAOAEP} from "src/lib/RSA.sol";
import {uint2str} from "src/lib/Uint2Str.sol";
import {
    MaxPriorityQueue,
    Queue,
    Bid as QueueBid
} from "src/modules/auctions/LSBBA/MaxPriorityQueue.sol";

/// @title      LocalSealedBidBatchAuction
/// @notice     A completely on-chain sealed bid batch auction that uses RSA encryption to hide bids until after the auction ends
/// @dev        The auction occurs in three phases:
///             1. Bidding - bidders submit encrypted bids
///             2. Decryption - anyone with the private key can decrypt bids off-chain and submit them on-chain for validation and sorting
///             3. Settlement - once all bids are decryped, the auction can be settled and proceeds transferred
contract LocalSealedBidBatchAuction is AuctionModule {
    using MaxPriorityQueue for Queue;

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

    /// @notice        Struct containing encrypted bid data
    ///
    /// @param         status              The status of the bid
    /// @param         bidder              The address of the bidder
    /// @param         recipient           The address of the recipient
    /// @param         referrer            The address of the referrer
    /// @param         amount              The amount of the bid
    /// @param         encryptedAmountOut  The encrypted amount out
    struct EncryptedBid {
        BidStatus status;
        address bidder;
        address recipient;
        address referrer;
        uint256 amount;
        bytes encryptedAmountOut;
    }

    /// @notice        Struct containing decrypted bid data
    ///
    /// @param         amountOut           The amount out
    /// @param         seed                The seed used to encrypt the amount out
    struct Decrypt {
        uint256 amountOut;
        bytes32 seed;
    }

    /// @notice        Struct containing auction data
    ///
    /// @param         status              The status of the auction
    /// @param         nextDecryptIndex    The index of the next bid to decrypt
    /// @param         nextBidId           The ID of the next bid to be submitted
    /// @param         minimumPrice        The minimum price that the auction can settle at (in terms of quote token)
    /// @param         minFilled           The minimum amount of capacity that must be filled to settle the auction
    /// @param         minBidSize          The minimum amount that can be bid for the lot, determined by the percentage of capacity that must be filled per bid times the min bid price
    /// @param         publicKeyModulus    The public key modulus used to encrypt bids
    /// @param         bidIds              The list of bid IDs to decrypt in order of submission, excluding cancelled bids
    struct AuctionData {
        AuctionStatus status;
        uint96 nextDecryptIndex;
        uint96 nextBidId;
        uint256 minimumPrice;
        uint256 minFilled;
        uint256 minBidSize;
        bytes publicKeyModulus;
        uint96[] bidIds;
    }

    /// @notice         Struct containing parameters for creating a new LSBBA auction
    ///
    /// @param          minFillPercent_     The minimum percentage of the lot capacity that must be filled for the auction to settle (scale: `_ONE_HUNDRED_PERCENT`)
    /// @param          minBidPercent_      The minimum percentage of the lot capacity that must be bid for each bid (scale: `_ONE_HUNDRED_PERCENT`)
    /// @param          minimumPrice_       The minimum price that the auction can settle at (in terms of quote token)
    /// @param          publicKeyModulus_   The public key modulus used to encrypt bids
    struct AuctionDataParams {
        uint24 minFillPercent;
        uint24 minBidPercent;
        uint256 minimumPrice;
        bytes publicKeyModulus;
    }

    // ========== STATE VARIABLES ========== //

    uint24 internal constant _MIN_BID_PERCENT = 1000; // 1%
    uint24 internal constant _PUB_KEY_EXPONENT = 65_537;

    mapping(uint96 lotId => AuctionData) public auctionData;
    mapping(uint96 lotId => mapping(uint96 bidId => EncryptedBid bid)) public lotEncryptedBids;
    mapping(uint96 lotId => Queue) public lotSortedBids;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
        // Set the minimum auction duration to 1 day initially
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

    /// @notice     Reverts if the lot has already been decrypted
    function _revertIfLotDecrypted(uint96 lotId_) internal view {
        // Check that bids are allowed to be submitted for the lot
        if (auctionData[lotId_].status == AuctionStatus.Decrypted) revert Auction_WrongState();
    }

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the lot is not yet settled
    function _revertIfLotSettled(uint96 lotId_) internal view override {
        // Auction must not be settled
        if (auctionData[lotId_].status == AuctionStatus.Settled) {
            revert Auction_WrongState();
        }
    }

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the bid is valid
    function _revertIfBidInvalid(uint96 lotId_, uint96 bidId_) internal view override {
        // Bid ID must be less than number of bids for lot
        if (bidId_ >= auctionData[lotId_].nextBidId) revert Auction_InvalidBidId(lotId_, bidId_);
    }

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the sender is the bidder
    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint96 bidId_,
        address bidder_
    ) internal view override {
        // Check that sender is the bidder
        if (bidder_ != lotEncryptedBids[lotId_][bidId_].bidder) revert Auction_NotBidder();
    }

    /// @inheritdoc AuctionModule
    /// @dev        Checks that the bid is not already cancelled
    function _revertIfBidCancelled(uint96 lotId_, uint96 bidId_) internal view override {
        // Bid must not be cancelled
        if (lotEncryptedBids[lotId_][bidId_].status == BidStatus.Cancelled) {
            revert Auction_AlreadyCancelled();
        }
    }

    // =========== BID =========== //

    /// @inheritdoc AuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Stores the encrypted bid
    ///             - Adds the bid ID to the list of bids to decrypt (in `AuctionData.bidIds`)
    ///             - Returns the bid ID
    ///
    ///             Typically, the `_bid()` function would check whether the bid is of a minimum size and less than the capacity. As `Bid.minAmountOut` is encrypted, it is not possible to check this here. Instead, this is checked in `_settle()`.
    ///
    ///             This function reverts if:
    ///             - The amount is less than the minimum bid size for the lot
    function _bid(
        uint96 lotId_,
        address bidder_,
        address recipient_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) internal override returns (uint96 bidId) {
        // Validate inputs

        // Does not check that the bid amount (in terms of the quote token) is less than the minimum bid size (in terms of the base token), because they are different units

        // Does not check that the bid amount (in terms of the quote token) is greater than the lot capacity (in terms of the base token), because they are different units

        // Store bid data
        // Auction data should just be the encrypted amount out (no decoding required)
        EncryptedBid memory userBid;
        userBid.bidder = bidder_;
        userBid.recipient = recipient_;
        userBid.referrer = referrer_;
        userBid.amount = amount_;
        userBid.encryptedAmountOut = auctionData_;
        userBid.status = BidStatus.Submitted;

        // Get next bid ID and increment it after assignment
        bidId = auctionData[lotId_].nextBidId++;

        // Store bid in mapping and add bid ID to list of bids to decrypt
        lotEncryptedBids[lotId_][bidId] = userBid;
        auctionData[lotId_].bidIds.push(bidId);

        return bidId;
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Marks the bid as cancelled
    ///             - Removes the bid from the list of bids to decrypt
    ///             - Returns the amount to be refunded
    ///
    ///             The encrypted bid is not deleted from storage, so that the details can be fetched later.
    ///
    ///             This function reverts if:
    ///             - The bid is not in the Submitted state
    ///             - The auction is not in the Created state
    function _cancelBid(
        uint96 lotId_,
        uint96 bidId_,
        address
    ) internal override returns (uint256 refundAmount) {
        // Validate inputs

        // Bid must be in Submitted state
        if (lotEncryptedBids[lotId_][bidId_].status != BidStatus.Submitted) {
            revert Auction_WrongState();
        }

        // Auction must be in Created state
        if (auctionData[lotId_].status != AuctionStatus.Created) revert Auction_WrongState();

        // Set bid status to cancelled
        lotEncryptedBids[lotId_][bidId_].status = BidStatus.Cancelled;

        // Remove bid from list of bids to decrypt
        uint96[] storage bidIds = auctionData[lotId_].bidIds;
        uint256 len = bidIds.length;
        for (uint256 i; i < len; i++) {
            if (bidIds[i] == bidId_) {
                bidIds[i] = bidIds[len - 1];
                bidIds.pop();
                break;
            }
        }

        // Return the amount to be refunded
        return lotEncryptedBids[lotId_][bidId_].amount;
    }

    // =========== DECRYPTION =========== //

    /// @notice         Decrypts a batch of bids and sorts them
    ///                 This function expects a third-party with access to the lot's private key
    ///                 to decrypt the bids off-chain (after calling `getNextBidsToDecrypt()`) and
    ///                 submit them on-chain.
    /// @dev            Anyone can call this function, provided they have access to the private key to decrypt the bids.
    ///
    ///                 This function handles the following:
    ///                 - Performs validation
    ///                 - Iterates over the decrypted bids:
    ///                     - Re-encrypts the decrypted bid to confirm that it matches the stored encrypted bid
    ///                     - Stores the decrypted bid in the sorted bid queue
    ///                     - Sets the encrypted bid status to decrypted
    ///                 - Determines the next decrypt index
    ///                 - Sets the auction status to decrypted if all bids have been decrypted
    ///
    ///                 This function reverts if:
    ///                 - The lot ID is invalid
    ///                 - The lot has not concluded
    ///                 - The lot has already been decrypted in full
    ///                 - The number of decrypts is greater than the number of bids remaining to be decrypted
    ///                 - The encrypted bid does not match the re-encrypted decrypt
    ///
    /// @param          lotId_          The lot ID of the auction to decrypt bids for
    /// @param          decrypts_       An array of decrypts containing the amount out and seed for each bid
    function decryptAndSortBids(uint96 lotId_, Decrypt[] memory decrypts_) external {
        // Check that lotId is valid
        _revertIfLotInvalid(lotId_);

        // Check that auction is in the right state for decryption
        if (
            auctionData[lotId_].status != AuctionStatus.Created
                || block.timestamp < lotData[lotId_].conclusion
        ) revert Auction_WrongState();

        // Load next decrypt index
        uint96 nextDecryptIndex = auctionData[lotId_].nextDecryptIndex;
        uint96 len = uint96(decrypts_.length);

        // Check that the number of decrypts is less than or equal to the number of bids remaining to be decrypted
        uint96[] storage bidIds = auctionData[lotId_].bidIds;
        if (len > bidIds.length - nextDecryptIndex) {
            revert Auction_InvalidDecrypt();
        }

        // Iterate over decrypts, validate that they match the stored encrypted bids, then store them in the sorted bid queue
        for (uint96 i; i < len; i++) {
            // Re-encrypt the decrypt to confirm that it matches the stored encrypted bid
            bytes memory ciphertext = _encrypt(lotId_, decrypts_[i]);

            // Load encrypted bid
            uint96 bidId = bidIds[nextDecryptIndex + i];
            EncryptedBid storage encBid = lotEncryptedBids[lotId_][bidId];

            // Check that the encrypted bid matches the re-encrypted decrypt by hashing both
            if (keccak256(ciphertext) != keccak256(encBid.encryptedAmountOut)) {
                revert Auction_InvalidDecrypt();
            }

            if (encBid.status != BidStatus.Submitted) continue;

            // Store the decrypt in the sorted bid queue
            lotSortedBids[lotId_].insert(bidId, encBid.amount, decrypts_[i].amountOut);

            // Set bid status to decrypted
            encBid.status = BidStatus.Decrypted;
        }

        // Increment next decrypt index
        auctionData[lotId_].nextDecryptIndex += len;

        // If all bids have been decrypted, set auction status to decrypted
        if (auctionData[lotId_].nextDecryptIndex == bidIds.length) {
            auctionData[lotId_].status = AuctionStatus.Decrypted;
        }
    }

    /// @notice         Re-encrypts a decrypt to confirm that it matches the stored encrypted bid
    function _encrypt(
        uint96 lotId_,
        Decrypt memory decrypt_
    ) internal view returns (bytes memory) {
        return RSAOAEP.encrypt(
            abi.encodePacked(decrypt_.amountOut),
            abi.encodePacked(uint2str(uint256(lotId_))),
            abi.encodePacked(_PUB_KEY_EXPONENT),
            auctionData[lotId_].publicKeyModulus,
            decrypt_.seed
        );
    }

    /// @notice         View function that can be used to obtain a certain number of the next bids to decrypt off-chain
    /// @dev            This function can be called by anyone, and is used by the decryptAndSortBids() function to obtain the next bids to decrypt
    ///
    ///                 This function handles the following:
    ///                 - Validates inputs
    ///                 - Loads the next decrypt index
    ///                 - Loads the number of bids to decrypt
    ///                 - Creates an array of encrypted bids
    ///                 - Returns the array of encrypted bids
    ///
    ///                 This function reverts if:
    ///                 - The lot ID is invalid
    ///                 - The lot has not concluded
    ///                 - The lot has already been decrypted in full
    ///                 - The number of bids to decrypt is greater than the number of bids remaining to be decrypted
    ///
    /// @param          lotId_          The lot ID of the auction to decrypt bids for
    /// @param          number_         The number of bids to decrypt
    /// @return         bids            An array of encrypted bids
    function getNextBidsToDecrypt(
        uint96 lotId_,
        uint256 number_
    ) external view returns (EncryptedBid[] memory) {
        // Validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotActive(lotId_);
        _revertIfLotDecrypted(lotId_);
        _revertIfLotSettled(lotId_);

        // Load next decrypt index
        uint96 nextDecryptIndex = auctionData[lotId_].nextDecryptIndex;

        // Load number of bids to decrypt
        uint96[] storage bidIds = auctionData[lotId_].bidIds;

        // Check that the number of bids to decrypt is less than or equal to the number of bids remaining to be decrypted
        if (number_ > bidIds.length - nextDecryptIndex) revert Auction_InvalidDecrypt();

        uint256 len = bidIds.length - nextDecryptIndex;
        if (number_ < len) len = number_;

        // Create array of encrypted bids
        EncryptedBid[] memory bids = new EncryptedBid[](len);

        // Iterate over bids and add them to the array
        for (uint256 i; i < len; i++) {
            bids[i] = lotEncryptedBids[lotId_][bidIds[nextDecryptIndex + i]];
        }

        // Return array of encrypted bids
        return bids;
    }

    // =========== SETTLEMENT =========== //

    /// @notice     Calculates the marginal clearing price of the auction
    ///
    /// @param      lotId_              The lot ID of the auction to calculate the marginal price for
    /// @return     marginalPrice       The marginal clearing price of the auction (in quote token units)
    /// @return     numWinningBids      The number of winning bids
    function _calculateMarginalPrice(uint96 lotId_)
        internal
        view
        returns (uint256 marginalPrice, uint256 numWinningBids)
    {
        // Cache capacity and scaling values
        // Capacity is always in base token units for this auction type
        uint256 capacity = lotData[lotId_].capacity;
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;

        // Iterate over bid queue to calculate the marginal clearing price of the auction
        Queue storage queue = lotSortedBids[lotId_];
        uint256 numBids = queue.getNumBids();
        uint256 totalAmountIn;
        for (uint256 i = 0; i < numBids; i++) {
            // Load bid
            QueueBid storage qBid = queue.getBid(uint96(i));

            // Calculate bid price (in quote token units)
            // quote scale * base scale / base scale = quote scale
            uint256 price = (qBid.amountIn * baseScale) / qBid.minAmountOut;

            // Increment total amount in
            totalAmountIn += qBid.amountIn;

            // Determine total capacity expended at this price (in base token units)
            // quote scale * base scale / quote scale = base scale
            uint256 expended = (totalAmountIn * baseScale) / price;

            // If total capacity expended is greater than or equal to the capacity, we have found the marginal price
            if (expended >= capacity) {
                marginalPrice = price;
                numWinningBids = i + 1;
                break;
            }

            // If we have reached the end of the queue, we have found the marginal price and the maximum capacity that can be filled
            if (i == numBids - 1) {
                // If the total filled is less than the minimum filled, mark as settled and return no winning bids (so users can claim refunds)
                if (expended < auctionData[lotId_].minFilled) {
                    return (0, 0);
                } else {
                    marginalPrice = price;
                    numWinningBids = numBids;
                }
            }
        }

        // Check if the minimum price for the auction was reached
        // If not, mark as settled and return no winning bids (so users can claim refunds)
        if (marginalPrice < auctionData[lotId_].minimumPrice) {
            return (0, 0);
        }

        return (marginalPrice, numWinningBids);
    }

    /// @inheritdoc AuctionModule
    /// @dev        This function performs the following:
    ///             - Validates inputs
    ///             - Iterates over the bid queue to calculate the marginal clearing price of the auction
    ///             - Creates an array of winning bids
    ///             - Sets the auction status to settled
    ///             - Returns the array of winning bids
    ///
    ///             This function reverts if:
    ///             - The auction is not in the Decrypted state
    ///             - The auction has already been settled
    function _settle(uint96 lotId_)
        internal
        override
        returns (Bid[] memory winningBids_, bytes memory)
    {
        // Check that auction is in the right state for settlement
        if (auctionData[lotId_].status != AuctionStatus.Decrypted) revert Auction_WrongState();

        // Calculate marginal price and number of winning bids
        (uint256 marginalPrice, uint256 numWinningBids) = _calculateMarginalPrice(lotId_);

        // Check if a valid price was reached
        // If not, mark as settled and return no winning bids (so users can claim refunds)
        if (marginalPrice == 0) {
            auctionData[lotId_].status = AuctionStatus.Settled;
            return (winningBids_, bytes(""));
        }

        // Auction can be settled at the marginal price if we reach this point
        // Create winning bid array using marginal price to set amounts out
        Queue storage queue = lotSortedBids[lotId_];
        uint256 baseScale = 10 ** lotData[lotId_].baseTokenDecimals;
        winningBids_ = new Bid[](numWinningBids);
        for (uint256 i; i < numWinningBids; i++) {
            // Load bid
            QueueBid memory qBid = queue.popMax();

            // Calculate amount out (in base token units)
            // quote scale * base scale / quote scale = base scale
            // For partial bids, this will be the amount they would get at full value
            // The auction house handles reduction of payouts for partial bids
            uint256 amountOut = (qBid.amountIn * baseScale) / marginalPrice;

            // Create winning bid from encrypted bid and calculated amount out
            EncryptedBid storage encBid = lotEncryptedBids[lotId_][qBid.bidId];
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

        // minFillPercent must be less than or equal to 100%
        if (implParams.minFillPercent > _ONE_HUNDRED_PERCENT) revert Auction_InvalidParams();

        // minBidPercent must be greater than or equal to the global min and less than or equal to 100%
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
        auctionData[lotId_].status = AuctionStatus.Settled;
    }

    function payoutFor(
        uint96 lotId_,
        uint256 amount_
    ) public view virtual override returns (uint256) {}

    function priceFor(
        uint96 lotId_,
        uint256 payout_
    ) public view virtual override returns (uint256) {}

    function maxPayout(uint96 lotId_) public view virtual override returns (uint256) {}

    function maxAmountAccepted(uint96 lotId_) public view virtual override returns (uint256) {}

    function getLotData(uint96 lotId_) public view returns (AuctionData memory) {
        return auctionData[lotId_];
    }

    function getBidData(uint96 lotId_, uint96 bidId_) public view returns (EncryptedBid memory) {
        return lotEncryptedBids[lotId_][bidId_];
    }

    function getSortedBidData(uint96 lotId_, uint96 index_) public view returns (QueueBid memory) {
        return lotSortedBids[lotId_].getBid(index_);
    }

    function getSortedBidCount(uint96 lotId_) public view returns (uint256) {
        return lotSortedBids[lotId_].getNumBids();
    }

    /// @notice Single view function to return the data needed to lookup private key for an auction and determine the number of bids left to decrypt
    function getDecryptData(uint96 lotId_)
        public
        view
        returns (
            AuctionStatus status_,
            uint96 activeBids_,
            uint96 nextDecryptIndex_,
            bytes memory publicKeyModulus_
        )
    {
        AuctionData storage data = auctionData[lotId_];
        return
            (data.status, uint96(data.bidIds.length), data.nextDecryptIndex, data.publicKeyModulus);
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

    // ========== UTILS ========== //

    // Some fancy math to convert a uint into a string, courtesy of Provable Things.
    // Updated to work with solc 0.8.0.
    // https://github.com/provable-things/ethereum-api/blob/master/provableAPI_0.6.sol
    function _uint2str(uint96 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
