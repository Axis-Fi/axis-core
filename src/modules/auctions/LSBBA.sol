/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

// import "src/modules/auctions/bases/BatchAuction.sol";
import {AuctionModule} from "src/modules/Auction.sol";
import {Veecode, toVeecode, Module} from "src/modules/Modules.sol";
import {RSAOAEP} from "src/lib/RSA.sol";

// A completely on-chain sealed bid batch auction that uses RSA encryption to hide bids until after the auction ends
// The auction occurs in three phases:
// 1. Bidding - bidders submit encrypted bids
// 2. Decryption - anyone with the private key can decrypt bids off-chain and submit them on-chain for validation and sorting
// 3. Settlement - once all bids are decryped, the auction can be settled and proceeds transferred
// TODO abstract since not everything is implemented here
abstract contract LocalSealedBidBatchAuction is AuctionModule {

    // ========== ERRORS ========== //
    error Auction_BidDoesNotExist();
    error Auction_NotBidder();
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
        Settled,
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
        bytes publicKeyModulus;
        uint256 minimumPrice;
        uint256 minBidSize; // minimum amount that can be bid for the lot, determined by the percentage of capacity that must be filled per bid times the min bid price
        uint256 nextDecryptIndex;
    }

    // ========== STATE VARIABLES ========== //

    uint256 public constant PUB_KEY_EXPONENT = 65537; // TODO can be 3 to save gas
    uint256 public constant SCALE = 1e18; // TODO maybe set this per auction if decimals mess us up

    mapping(uint96 lotId => AuctionData) public auctionData;
    mapping(uint96 lotId => EncryptedBid[] bids) public lotBids;

    // ========== SETUP ========== //

    constructor(address auctionHouse_) AuctionModule(auctionHouse_) {
    }

    function VEECODE() public pure override returns (Veecode) {
        return toVeecode("01LSBBA");
    }

    function TYPE() public pure override returns (Type) {
        return Type.Auction;
    }

    // =========== BID =========== //
    function bid(uint96 lotId_, address recipient_, address referrer_, uint256 amount_, bytes calldata auctionData_) external onlyInternal returns (uint256 bidId) {
        // Check that bids are allowed to be submitted for the lot
        if (auctionData[lotId_].status != AuctionStatus.Created || block.timestamp < lotData[lotId_].start || block.timestamp >= lotData[lotId_].conclusion) revert Auction_NotLive();
        
        // Validate inputs
        // Amount at least minimum bid size for lot
        if (amount_ < auctionData[lotId_].minBidSize) revert Auction_WrongState();

        // Store bid data
        // Auction data should just be the encrypted amount out (no decoding required)
        EncryptedBid memory userBid;
        userBid.bidder = msg.sender;
        userBid.recipient = recipient_;
        userBid.referrer = referrer_;
        userBid.amount = amount_;
        userBid.encryptedAmountOut = auctionData_;
        userBid.status = BidStatus.Submitted;

        // Bid ID is the next index in the lot's bid array
        bidId = lotBids[lotId_].length;

        // Add bid to lot
        lotBids[lotId_].push(userBid);
    }

    function cancelBid(uint96 lotId_, uint96 bidId_, address sender_) external onlyInternal {

        // Validate inputs
        // Auction for lot must still be live
        if (auctionData[lotId_].status != AuctionStatus.Created || block.timestamp < lotData[lotId_].start || block.timestamp >= lotData[lotId_].conclusion) revert Auction_NotLive();

        // Bid ID must be less than number of bids for lot
        if (bidId_ >= lotBids[lotId_].length) revert Auction_BidDoesNotExist();

        // Sender must be bidder
        if (sender_ != lotBids[lotId_][bidId_].bidder) revert Auction_NotBidder();

        // Bid is not already cancelled
        if (lotBids[lotId_][bidId_].status != BidStatus.Submitted) revert Auction_AlreadyCancelled();

        // Set bid status to cancelled
        lotBids[lotId_][bidId_].status = BidStatus.Cancelled;
    }

    // =========== DECRYPTION =========== //

    function decryptAndSortBids(uint96 lotId_, Decrypt[] memory decrypts_) external {
        // Check that auction is in the right state for decryption
        if (auctionData[lotId_].status != AuctionStatus.Created || block.timestamp < lotData[lotId_].conclusion) revert Auction_WrongState();
        
        // Load next decrypt index
        uint256 nextDecryptIndex = auctionData[lotId_].nextDecryptIndex;
        uint256 len = decrypts_.length;

        // Iterate over decrypts, validate that they match the stored encrypted bids, then store them in the sorted bid queue
        for (uint256 i; i < len; i++) {
            // Re-encrypt the decrypt to confirm that it matches the stored encrypted bid
            bytes memory ciphertext = _encrypt(lotId_, decrypts_[i]);

            // Load encrypted bid
            EncryptedBid storage encBid = lotBids[lotId_][nextDecryptIndex + i];

            // Check that the encrypted bid matches the re-encrypted decrypt by hashing both
            if (keccak256(ciphertext) != keccak256(encBid.encryptedAmountOut)) revert Auction_InvalidDecrypt();

            // Derive price from bid amount and decrypt amount out
            uint256 price = (encBid.amount * SCALE) / decrypts_[i].amountOut;
            
            // Store the decrypt in the sorted bid queue
            // TODO need to determine which data structure to use for the queue

            // Set bid status to decrypted
            encBid.status = BidStatus.Decrypted;
        }

        // Increment next decrypt index
        auctionData[lotId_].nextDecryptIndex += len;

        // If all bids have been decrypted, set auction status to decrypted
        if (auctionData[lotId_].nextDecryptIndex == lotBids[lotId_].length) auctionData[lotId_].status = AuctionStatus.Decrypted;
    }

    function _encrypt(uint96 lotId_, Decrypt memory decrypt_) internal view returns (bytes memory) {
        return RSAOAEP.encrypt(abi.encodePacked(decrypt_.amountOut), abi.encodePacked(lotId_), abi.encodePacked(PUB_KEY_EXPONENT), auctionData[lotId_].publicKeyModulus, decrypt_.seed);
    }

    /// @notice View function that can be used to obtain the amount out and seed for a given bid by providing the private key
    /// @dev This function can be used to decrypt bids off-chain if you know the private key
    function decryptBid(uint96 lotId_, uint96 bidId_, bytes memory privateKey_) external view returns (Decrypt memory) {
        // Load encrypted bid
        EncryptedBid memory encBid = lotBids[lotId_][bidId_];

        // Decrypt the encrypted amount out
        (bytes memory amountOut, bytes32 seed) = RSAOAEP.decrypt(encBid.encryptedAmountOut, abi.encodePacked(lotId_), privateKey_, auctionData[lotId_].publicKeyModulus);

        // Cast the decrypted values
        Decrypt memory decrypt;
        decrypt.amountOut = abi.decode(amountOut, (uint256));
        decrypt.seed = uint256(seed);

        // Return the decrypt
        return decrypt;
    }


    // =========== SETTLEMENT =========== //

    function settle(uint96 lotId_) external onlyInternal returns (Bid[] memory winningBids_) {
        // Check that auction is in the right state for settlement
        if (auctionData[lotId_].status != AuctionStatus.Decrypted) revert Auction_WrongState();

        // Iterate over bid queue to calculate the marginal clearing price of the auction

        // Create winning bid array using marginal price to set amounts out

        // Set auction status to settled

        // Return winning bids
    }


    // =========== AUCTION MANAGEMENT ========== //

    // TODO auction creation
    // TODO auction cancellation?

}
