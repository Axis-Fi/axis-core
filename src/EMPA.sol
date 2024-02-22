/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ReentrancyGuard} from "lib/solmate/src/utils/ReentrancyGuard.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {MaxPriorityQueue, Queue, Bid as QueueBid} from "src/lib/MaxPriorityQueue.sol";
import {ECIES, Point} from "src/lib/ECIES.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {DerivativeModule} from "src/modules/Derivative.sol";

import {
    Veecode,
    fromVeecode,
    Keycode,
    fromKeycode,
    WithModules,
    Module
} from "src/modules/Modules.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";

/// @title      Router
/// @notice     An interface to define the routing of transactions to the appropriate auction module
abstract contract Router {
    // ========== BATCH AUCTIONS ========== //

    /// @notice     Bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Store the bid
    ///             3. Transfer the amount of quote token from the bidder
    ///
    /// @param      lotId_               Lot ID
    /// @param      referrer_            Address of referrer
    /// @param      amount_              Amount of quoteToken to purchase with (in native decimals)
    /// @param      encryptedAmountOut_  Encrypted amount out. The amount out should be no larger than the max uint96 value. We also use a random seed to obscure leading zero bytes. See _decrypt for more details.
    /// @param      bidPubKey_           Public key of the shared secret (used to encrypt the amount out)
    /// @param      allowlistProof_      Proof of allowlist inclusion
    /// @param      permit2Data_         Permit2 approval for the quoteToken (abi-encoded Permit2Approval struct)
    /// @return     bidId                Bid ID
    ///
    ///  The contract expects the encryptedAmountOut and bidPubKey to be generated in a specific way:
    ///
    ///  Formatting the amount to encrypt:
    ///  1. The amount is expected to be a uint96 padded to 16 bytes (128 bits).
    ///  2. A random 128-bit seed should be generated to mask the actual value of the amount.
    ///  3. The value to encrypt should be subtracted from the seed.
    ///  4. The seed and the subtracted result should be concatenated to form the message for encryption.
    ///  We do this to avoid leading zero bytes in the plaintext, which would make it easier for an attacker to decrypt.
    ///
    ///  Pseudo-code using Solidity types:
    ///  uint96 amountOut = {AMOUNT_OUT_TO_BID};
    ///  uint128 seed = RNG(); // some source of randomness
    ///  uint128 subtracted;
    ///  unchecked { subtracted = seed - uint128(amountOut); }
    ///  uint256 message = uint256(abi.encodePacked(seed, subtracted));
    ///
    ///  Note that the `subtracted` value is allowed to underflow, which is why we use unchecked.
    ///
    ///  Then, the message should be encrypted as follows (off-chain):
    ///  1. Generate a value to serve as the bid private key
    ///  2. Calculate the bid public key using the bid private key
    ///  3. Calculate a shared secret public key using the bid public key and the auction public key
    ///  4. Calculate the salt to use to derive the symmetric key by taking the keccak256 hash of the lot ID, bidder address, and amountIn (the amount of the bid)
    ///  5. Calculate the symmetric key by taking the keccak256 hash of the x coordinate of shared secret public key and the salt
    ///  6. Encrypt the message by XORing the message with the symmetric key
    ///
    ///  Pseudo-code using Solidity types:
    ///  uint256 bidPrivateKey = RNG(); // some source of randomness, derived specifically for this bid
    ///  Point memory bidPubKey = ecMul(Point(1,2), bidPrivateKey); // scalar multiplication of (1, 2) point by the scalar bidPrivateKey
    ///  Point memory sharedSecretPubKey = ecMul(auctionPublicKey, bidPrivateKey); // scalar multiplication of the auctionPublicKey point by the scalar bidPrivateKey
    ///  uint256 salt = uint256(keccak256(abi.encodePacked(lotId, bidder, amountIn)));
    ///  uint256 symmetricKey = uint256(keccak256(abi.encodePacked(sharedSecretPubKey.x, salt)));
    ///  uint256 encryptedAmountOut = message ^ symmetricKey;
    ///
    ///  Submit the encryptedAmountOut and the bidPubKey as part of the bid transaction.
    function bid(
        uint96 lotId_,
        address referrer_,
        uint96 amount_,
        uint256 encryptedAmountOut_,
        Point calldata bidPubKey_,
        bytes calldata allowlistProof_,
        bytes calldata permit2Data_
    ) external virtual returns (uint64 bidId);

    /// @notice     Refund a bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Send the refund to the bidder
    ///
    /// @param      lotId_          Lot ID
    /// @param      bidId_          Bid ID
    function refundBid(uint96 lotId_, uint64 bidId_) external virtual;

    /// @notice     Settle a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the lot
    ///             2. Calculate the marginal price
    ///             3. Calculate the winning bids
    ///             4. If the last bid is not fully filled, refund the remaining amount
    ///             5. Send payment to the auction owner
    ///             6. Refund any unused capacity to the auction owner
    ///             7. Distribute curator fees
    ///
    /// @param      lotId_          Lot ID
    function settle(uint96 lotId_) external virtual;

    /// @notice     Claim the proceeds or refund from a settled batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the lot and bid
    ///             2. If the bid price is less than the marginal price, it refunds the bid amount to the bidder
    ///             3. If the bid price is greater than or equal to the marginal price, it sends the payout to the bidder and allocates fees
    ///
    /// @param      lotId_          Lot ID
    /// @param      bidId_          Bid ID
    function claim(uint96 lotId_, uint64 bidId_) external virtual;
}

/// @title      FeeManager
/// @notice     Defines fees for auctions and manages the collection and distribution of fees
abstract contract FeeManager is Owned, ReentrancyGuard {
    // ========== ERRORS ========== //

    error InvalidFee();

    // ========== DATA STRUCTURES ========== //

    /// @notice     Collection of fees charged for a specific auction type in basis points (3 decimals).
    /// @notice     Protocol and referrer fees are taken in the quoteToken and accumulate in the contract. These are set by the protocol.
    /// @notice     Curator fees are taken in the payoutToken and are sent when the auction is settled / purchase is made. Curators can set these up to the configured maximum.
    /// @dev        There are some situations where the fees may round down to zero if quantity of baseToken
    ///             is < 1e5 wei (can happen with big price differences on small decimal tokens). This is purely
    ///             a theoretical edge case, as the amount would not be practical.
    ///
    /// @param      protocol        Fee charged by the protocol
    /// @param      referrer        Fee charged by the referrer
    /// @param      maxCuratorFee   Maximum fee that a curator can charge
    /// @param      curator         Fee charged by a specific curator
    struct Fees {
        uint24 protocol;
        uint24 referrer;
        uint24 maxCuratorFee;
        mapping(address => uint24) curator;
    }

    enum FeeType {
        Protocol,
        Referrer,
        MaxCurator
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     Fees are in basis points (3 decimals). 1% equals 1000.
    uint24 internal constant _FEE_DECIMALS = 1e5;

    /// @notice     Address the protocol receives fees at
    address internal _protocol;

    /// @notice     Fees charged for each auction type
    /// @dev        See Fees struct for more details
    Fees public fees;

    /// @notice     Fees earned by an address, by token
    mapping(address => mapping(ERC20 => uint256)) public rewards;

    // ========== CONSTRUCTOR ========== //

    constructor(address protocol_) {
        _protocol = protocol_;
    }

    // ========== FEE CALCULATIONS ========== //

    /// @notice     Calculates and allocates fees that are collected in the quote token
    function calculateQuoteFees(
        bool hasReferrer_,
        uint96 amount_
    ) public view returns (uint96 toReferrer, uint96 toProtocol) {
        // Load protocol and referrer fees for the auction type
        uint24 protocolFee = fees.protocol;
        uint24 referrerFee = fees.referrer;

        if (hasReferrer_) {
            // In this case we need to:
            // 1. Calculate referrer fee
            // 2. Calculate protocol fee as the total expected fee amount minus the referrer fee
            //    to avoid issues with rounding from separate fee calculations
            toReferrer = (amount_ * referrerFee) / _FEE_DECIMALS;
            toProtocol = ((amount_ * (protocolFee + referrerFee)) / _FEE_DECIMALS) - toReferrer;
        } else {
            // There is no referrer
            toProtocol = (amount_ * (protocolFee + referrerFee)) / _FEE_DECIMALS;
        }
    }

    /// @notice     Calculates and allocates fees that are collected in the payout token
    function _calculatePayoutFees(
        address curator_,
        uint96 payout_
    ) internal view returns (uint96 toCurator) {
        // Calculate curator fee
        toCurator = (payout_ * fees.curator[curator_]) / _FEE_DECIMALS;
    }

    // ========== FEE MANAGEMENT ========== //

    /// @notice     Sets the protocol fee, referrer fee, or max curator fee for a specific auction type
    /// @notice     Access controlled: only owner
    function setFee(FeeType type_, uint24 fee_) external onlyOwner {
        // Check that the fee is a valid percentage
        if (fee_ > _FEE_DECIMALS) revert InvalidFee();

        // Set fee based on type
        // TODO should we have hard-coded maximums for these fees?
        // Or a combination of protocol and referrer fee since they are both in the quoteToken?
        if (type_ == FeeType.Protocol) {
            fees.protocol = fee_;
        } else if (type_ == FeeType.Referrer) {
            fees.referrer = fee_;
        } else if (type_ == FeeType.MaxCurator) {
            fees.maxCuratorFee = fee_;
        }
    }

    /// @notice     Sets the fee for a curator (the sender) for a specific auction type
    function setCuratorFee(uint24 fee_) external {
        // Check that the fee is less than the maximum
        if (fee_ > fees.maxCuratorFee) revert InvalidFee();

        // Set the fee for the sender
        fees.curator[msg.sender] = fee_;
    }

    /// @notice     Claims the rewards for a specific token and the sender
    /// @dev        This function reverts if:
    ///             - re-entrancy is detected
    ///
    /// @param      token_  Token to claim rewards for
    function claimRewards(address token_) external nonReentrant {
        ERC20 token = ERC20(token_);
        uint256 amount = rewards[msg.sender][token];
        rewards[msg.sender][token] = 0;

        Transfer.transfer(token, msg.sender, amount, false);
    }

    /// @notice     Sets the protocol address
    /// @dev        Access controlled: only owner
    ///
    /// @param      protocol_  Address of the protocol
    function setProtocol(address protocol_) external onlyOwner {
        _protocol = protocol_;
    }
}

/// @title      Encrypted Marginal Price Auction (EMPA)
contract EncryptedMarginalPriceAuction is WithModules, Router, FeeManager {
    using MaxPriorityQueue for Queue;

    // ========== ERRORS ========== //

    error AmountLessThanMinimum();
    error Broken_Invariant();
    error InvalidParams();
    error InvalidHook();
    error Overflow();

    error Auction_InvalidId(uint96 id_);
    error Auction_MarketActive(uint96 lotId); // TODO consider removing these two
    error Auction_MarketNotActive(uint96 lotId);
    error Auction_WrongState();

    error Bid_InvalidId(uint96 lotId, uint96 bidId);
    error Bid_AlreadyClaimed();
    error Bid_InvalidPublicKey();
    error Bid_InvalidPrivateKey();
    error Bid_WrongState();

    /// @notice     Used when the caller is not permitted to perform that action
    error NotPermitted(address caller_);

    // ========= EVENTS ========= //

    event AuctionCreated(uint96 indexed lotId, string ipfsHash);
    event AuctionCancelled(uint96 indexed lotId);
    event BidSubmitted(
        uint96 indexed lotId, uint96 indexed bidId, address indexed bidder, uint256 amount
    );
    event BidDecrypted(
        uint96 indexed lotId, uint96 indexed bidId, uint256 amountIn, uint256 amountOut
    );
    event Claimed(
        uint96 indexed lotId, uint64 indexed bidId, uint256 quoteAmount, uint256 payoutAmount
    );
    event Curated(uint96 indexed lotId, address indexed curator);
    event RefundBid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder); // replace or merge with claim?
    event Settle(uint96 indexed lotId);

    // ========= DATA STRUCTURES ========== //

    /// @notice     Auction routing information for a lot
    /// @dev        Variables arranged to maximize packing
    /// @param      baseToken           Token provided by seller
    /// @param      owner               ID of Lot owner
    /// @param      quoteToken          Token to accept as payment
    /// @param      curator             ID of the proposed curator
    /// @param      curated             Whether the curator has approved the auction
    /// @param      curatorFee          Amount of payout tokens the curator will receive if the auction is completely filled
    /// @param      hooks               (optional) Address to call for any hooks to be executed
    /// @param      allowlist           (optional) Contract that implements an allowlist for the auction lot
    /// @param      derivativeReference (optional) Derivative module, represented by its Veecode
    /// @param      wrapDerivative      (optional) Whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format
    /// @param      derivativeParams    (optional) abi-encoded data to be used to create payout derivatives on a purchase
    struct Routing {
        address owner; // 20 = slot 1
        ERC20 baseToken; // 20 = slot 2
        ERC20 quoteToken; // 20 = slot 3
        address curator; // 20 +
        uint96 curatorFee; // 12 = 32 - end of slot 4
        bool curated; // 1 +
        IHooks hooks; // 20 = 32 - end of slot 5
        IAllowlist allowlist; // 20 +
        Veecode derivativeReference; // 7 +
        bool wrapDerivative; // 1 = 28 - end of slot 6
        bytes derivativeParams; // slots 7+
    }

    /// @notice     Auction routing information provided as input parameters
    /// @dev        After validation, this information is stored in the Routing struct
    ///
    /// @param      baseToken       Token provided by seller
    /// @param      quoteToken      Token to accept as payment
    /// @param      curator         (optional) Address of the proposed curator
    /// @param      hooks           (optional) Address to call for any hooks to be executed
    /// @param      allowlist       (optional) Contract that implements an allowlist for the auction lot
    /// @param      allowlistParams (optional) abi-encoded data to be used to register the auction on the allowlist
    /// @param      derivativeType  (optional) Derivative type, represented by the Keycode for the derivative submodule
    /// @param      wrapDerivative  (optional) Whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format
    /// @param      derivativeParams (optional) abi-encoded data to be used to create payout derivatives on a purchase. The format of this is dependent on the derivative module.
    struct RoutingParams {
        ERC20 baseToken;
        ERC20 quoteToken;
        address curator;
        IHooks hooks;
        IAllowlist allowlist;
        bytes allowlistParams;
        Keycode derivativeType;
        bool wrapDerivative;
        bytes derivativeParams;
    }

    enum AuctionStatus {
        Created,
        Decrypted,
        Settled
    }

    enum BidStatus {
        Submitted,
        Decrypted,
        Claimed,
        Refunded
    }

    /// @notice        Struct containing encrypted bid data
    ///
    /// @param         bidder              The address of the bidder
    /// @param         amount              The amount of the bid
    /// @param         minAmountOut        The minimum amount out (not set until the bid is decrypted)
    /// @param         referrer            The address of the referrer
    /// @param         status              The status of the bid
    struct Bid {
        address bidder; // 20 +
        uint96 amount; // 12 = 32 - end of slot 1
        uint96 minAmountOut; // 12 +
        address referrer; // 20 = 32 - end of slot 2
        BidStatus status; // slot 3
    }

    /// @notice        Struct containing data for an encrypted bid
    ///
    /// @param         encryptedAmountOut  The encrypted amount out, the bid amount is encrypted with a symmetric key that can be derived from the bidPubKey using the private key for the provided auction public key on the alt_bn128 curve
    /// @param         bidPubKey           The alt_bn128 public key used to encrypt the amount out (see bid() for more details)
    struct EncryptedBid {
        uint256 encryptedAmountOut;
        Point bidPubKey;
    }

    /// @notice        Struct containing auction-level bid data
    ///
    /// @param         nextBidId           The ID of the next bid to be submitted
    /// @param         nextDecryptIndex    The index of the next bid to decrypt
    /// @param         marginalPrice       The marginal price of the auction (determined at settlement, blank before)
    /// @param         publicKey           The public key used to encrypt bids (a point on the alt_bn128 curve from the generator point (1,2))
    /// @param         privateKey          The private key used to decrypt bids (not provided until after the auction ends)
    /// @param         bidIds              The list of bid IDs to decrypt in order of submission, excluding cancelled bids
    struct BidData {
        uint64 nextBidId; // 8 +
        uint64 nextDecryptIndex; // 8 +
        uint96 marginalPrice; // 12 = 28 - end of slot 1
        Point publicKey; // 2 slots
        uint256 privateKey; // 1 slot
        uint64[] bidIds;
    }

    /// @notice     Core data for an auction lot
    ///
    /// @param      minimumPrice        The minimum price that the auction can settle at (in terms of quote token)
    /// @param      capacity            The capacity of the lot
    /// @param      quoteTokenDecimals  The quote token decimals
    /// @param      baseTokenDecimals   The base token decimals
    /// @param      start               The timestamp when the auction starts
    /// @param      conclusion          The timestamp when the auction ends
    /// @param      status              The status of the auction
    /// @param      minFilled           The minimum amount of capacity that must be filled to settle the auction
    /// @param      minBidSize          The minimum amount of tokens that must be expected for each bid (in base tokens)
    struct Lot {
        uint96 minimumPrice; // 12 +
        uint96 capacity; // 12 +
        uint8 quoteTokenDecimals; // 1 +
        uint8 baseTokenDecimals; // 1 +
        uint48 start; // 6 = 32 - end of slot 1
        uint48 conclusion; // 6 +
        AuctionStatus status; // 1 +
        uint96 minFilled; // 12 +
        uint96 minBidSize; // 12 = 31 - end of slot 2
    }

    /// @notice     Parameters when creating an auction lot
    ///
    /// @param      start               The timestamp when the auction starts
    /// @param      duration            The duration of the auction (in seconds)
    /// @param      minFillPercent_     The minimum percentage of the lot capacity that must be filled for the auction to settle (scale: `_ONE_HUNDRED_PERCENT`)
    /// @param      minBidPercent_      The minimum percentage of the lot capacity that must be bid for each bid (scale: `_ONE_HUNDRED_PERCENT`)
    /// @param      capacityInQuote     Whether or not the capacity is in quote tokens
    /// @param      capacity            The capacity of the lot
    /// @param      minimumPrice_       The minimum price that the auction can settle at (in terms of quote token)
    /// @param      publicKey_          The alt_bn128 public key for the auctions, used to encrypt bids
    struct AuctionParams {
        uint48 start;
        uint48 duration;
        uint24 minFillPercent;
        uint24 minBidPercent;
        uint96 capacity;
        uint96 minimumPrice;
        Point publicKey;
    }

    // ========= STATE ========== //

    /// @notice Constant for percentages
    /// @dev    1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint24 internal constant _ONE_HUNDRED_PERCENT = 100_000;
    uint24 internal constant _MIN_BID_PERCENT = 10; // 0.01%

    uint64 internal _nextUserId;

    address internal immutable _PERMIT2;

    /// @notice Minimum auction duration in seconds
    uint48 public minAuctionDuration;

    /// @notice     Counter for auction lots
    uint96 public lotCounter;

    // We use this to store addresses once and reference them using a shorter identifier
    mapping(address user => uint64) public userIds;

    /// @notice     General information pertaining to auction lots
    mapping(uint96 lotId => Lot lot) public lotData;

    /// @notice     Lot routing information
    mapping(uint96 lotId => Routing) public lotRouting;

    /// @notice     Auction-level bid data for a lot
    mapping(uint96 lotId => BidData) public bidData;

    /// @notice     Data for specific bids on a lot
    mapping(uint96 lotId => mapping(uint64 bidId => Bid)) public bids;

    /// @notice     Data for encryption information for a specific bid
    mapping(uint96 lotId => mapping(uint64 bidId => EncryptedBid)) public encryptedBids; // each encrypted amount is 5 slots (length + 4 slots) due to using 1024-bit RSA encryption

    /// @notice     Queue of decrypted bids for a lot (populated on decryption)
    mapping(uint96 lotId => Queue) public decryptedBids;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address protocol_,
        address permit2_
    ) FeeManager(protocol_) WithModules(owner_) {
        _PERMIT2 = permit2_;
        _nextUserId = 1;
    }

    // ========== USER MANAGEMENT ========== //

    function _getUserId(address user) internal returns (uint64) {
        uint64 id = userIds[user];
        if (id == 0) {
            id = _nextUserId++;
            userIds[user] = id;
        }
        return id;
    }

    // ========== AUCTION MANAGEMENT ========== //

    /// @notice     Creates a new auction lot
    /// @dev        The function reverts if:
    ///             - The base token or quote token decimals are not within the required range
    ///             - Validation for the auction parameters fails
    ///             - The module for the optional specified derivative type is not installed
    ///             - Validation for the optional specified derivative type fails
    ///             - Registration for the optional allowlist fails
    ///             - The optional specified hooks contract is not a contract
    ///             - re-entrancy is detected
    ///
    /// @param      routing_    Routing information for the auction lot
    /// @param      params_     Auction parameters for the auction lot
    /// @return     lotId       ID of the auction lot
    function auction(
        RoutingParams calldata routing_,
        AuctionParams calldata params_,
        string calldata ipfsHash
    ) external nonReentrant returns (uint96 lotId) {
        // Validate routing parameters

        if (address(routing_.baseToken) == address(0) || address(routing_.quoteToken) == address(0))
        {
            revert InvalidParams();
        }

        // Confirm tokens are within the required decimal range
        uint8 baseTokenDecimals = routing_.baseToken.decimals();
        uint8 quoteTokenDecimals = routing_.quoteToken.decimals();

        if (
            baseTokenDecimals < 6 || baseTokenDecimals > 18 || quoteTokenDecimals < 6
                || quoteTokenDecimals > 18
        ) revert InvalidParams();

        // Increment lot count and get ID
        lotId = lotCounter++;

        // Start time must be zero or in the future
        if (params_.start > 0 && params_.start < uint48(block.timestamp)) {
            revert InvalidParams();
        }

        // Duration must be at least min duration
        if (params_.duration < minAuctionDuration) {
            revert InvalidParams();
        }

        // minFillPercent must be less than or equal to 100%
        if (params_.minFillPercent > _ONE_HUNDRED_PERCENT) revert InvalidParams();

        // minBidPercent must be greater than or equal to the global min and less than or equal to 100%
        if (
            params_.minBidPercent < _MIN_BID_PERCENT || params_.minBidPercent > _ONE_HUNDRED_PERCENT
        ) {
            revert InvalidParams();
        }

        // Create core market data
        {
            Lot storage lot = lotData[lotId];
            lot.start = params_.start == 0 ? uint48(block.timestamp) : params_.start;
            lot.conclusion = lot.start + params_.duration;
            lot.quoteTokenDecimals = quoteTokenDecimals;
            lot.baseTokenDecimals = baseTokenDecimals;
            lot.capacity = params_.capacity;
            lot.minimumPrice = params_.minimumPrice;
            lot.minFilled = (params_.capacity * params_.minFillPercent) / _ONE_HUNDRED_PERCENT;
            lot.minBidSize = (params_.capacity * params_.minBidPercent) / _ONE_HUNDRED_PERCENT;
        }

        // Initialize bid data

        // publicKey must be a valid point on the alt_bn128 curve with generator point (1, 2)
        if (!ECIES.isOnBn128(params_.publicKey)) revert InvalidParams();

        // Check that the public key is not the generator point (i.e. private key is zero) or the point at infinity
        if (
            (params_.publicKey.x == 1 && params_.publicKey.y == 2)
                || (params_.publicKey.x == 0 && params_.publicKey.y == 0)
        ) {
            revert InvalidParams();
        }

        BidData storage data = bidData[lotId];
        data.publicKey = params_.publicKey;
        data.nextBidId = 1;
        decryptedBids[lotId].initialize();

        // Get user IDs for owner and curator
        Routing storage routing = lotRouting[lotId];
        {
            // Store routing information
            routing.owner = msg.sender;
            routing.baseToken = routing_.baseToken;
            routing.quoteToken = routing_.quoteToken;
            if (routing_.curator != address(0)) routing.curator = routing_.curator;
        }

        // Derivative
        if (fromKeycode(routing_.derivativeType) != bytes5("")) {
            // Load derivative module, this checks that it is installed.
            DerivativeModule derivativeModule =
                DerivativeModule(_getLatestModuleIfActive(routing_.derivativeType));
            Veecode derivativeRef = derivativeModule.VEECODE();

            // Check that the module for the derivative type is valid
            if (derivativeModule.TYPE() != Module.Type.Derivative) {
                revert InvalidParams();
            }

            // Call module validate function to validate implementation-specific data
            if (!derivativeModule.validate(address(routing.baseToken), routing_.derivativeParams)) {
                revert InvalidParams();
            }

            // Store derivative information
            routing.derivativeReference = derivativeRef;
            routing.wrapDerivative = routing_.wrapDerivative;
            routing.derivativeParams = routing_.derivativeParams;
        }

        // If allowlist is being used, validate the allowlist data and register the auction on the allowlist
        if (address(routing_.allowlist) != address(0)) {
            // Check that it is a contract
            // It is assumed that the user will do validation of the allowlist
            if (address(routing_.allowlist).code.length == 0) revert InvalidParams();

            // Register with the allowlist
            routing_.allowlist.register(lotId, routing_.allowlistParams);

            // Store allowlist information
            routing.allowlist = routing_.allowlist;
        }

        // Prefund the auction
        // If hooks are being used, validate the hooks data and then call the pre-auction create hook
        if (address(routing_.hooks) != address(0)) {
            // Check that it is a contract
            // It is assumed that the user will do validation of the hooks
            if (address(routing_.hooks).code.length == 0) revert InvalidParams();

            // Store hooks information
            routing.hooks = routing_.hooks;

            uint256 balanceBefore = routing_.baseToken.balanceOf(address(this));

            // The pre-auction create hook should transfer the base token to this contract
            routing_.hooks.preAuctionCreate(lotId);

            // Check that the hook transferred the expected amount of base tokens
            if (routing_.baseToken.balanceOf(address(this)) < balanceBefore + params_.capacity) {
                revert InvalidHook();
            }
        }
        // Otherwise fallback to a standard ERC20 transfer
        else {
            Transfer.transferFrom(
                routing_.baseToken, msg.sender, address(this), params_.capacity, true
            );

            // TODO check for fee on transfer
        }

        emit AuctionCreated(lotId, ipfsHash);
    }

    /// @notice     Cancels an auction lot
    /// @dev        This function performs the following:
    ///             - Checks that the lot ID is valid
    ///             - Checks that caller is the auction owner
    ///             - Updates records
    ///             - Refunds any remaining base tokens to the owner
    ///
    ///             The function reverts if:
    ///             - The lot ID is invalid
    ///             - The caller is not the auction owner
    ///             - The transfer of payout tokens fails
    ///             - re-entrancy is detected
    ///             - The auction lot has started
    ///             - The auction lot has concluded
    ///
    /// @param      lotId_      ID of the auction lot
    function cancel(uint96 lotId_) external nonReentrant {
        // Validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotActive(lotId_);
        _revertIfLotConcluded(lotId_);

        Routing storage routing = lotRouting[lotId_];

        // Check ownership
        if (msg.sender != routing.owner) revert NotPermitted(msg.sender);

        // Cache capacity and curator fee for refund
        Lot storage lot = lotData[lotId_];

        uint256 refund = lot.capacity + routing.curatorFee;
        lot.conclusion = uint48(block.timestamp);
        lot.capacity = 0;
        routing.curatorFee = 0;
        lot.status = AuctionStatus.Settled;

        // Refund base tokens to the owner
        Transfer.transfer(routing.baseToken, msg.sender, refund, false);

        emit AuctionCancelled(lotId_);
    }

    /// @notice     Determines if `caller_` is allowed to purchase/bid on a lot.
    ///             If no allowlist is defined, this function will return true.
    ///
    /// @param      allowlist_       Allowlist contract
    /// @param      lotId_           Lot ID
    /// @param      caller_          Address of caller
    /// @param      allowlistProof_  Proof of allowlist inclusion
    /// @return     bool             True if caller is allowed to purchase/bid on the lot
    function _isAllowed(
        IAllowlist allowlist_,
        uint96 lotId_,
        address caller_,
        bytes memory allowlistProof_
    ) internal view returns (bool) {
        if (address(allowlist_) == address(0)) {
            return true;
        } else {
            return allowlist_.isAllowed(lotId_, caller_, allowlistProof_);
        }
    }

    // ========== BIDDING ========== //

    /// @inheritdoc Router
    function bid(
        uint96 lotId_,
        address referrer_,
        uint96 amount_,
        uint256 encryptedAmountOut_,
        Point calldata bidPubKey_,
        bytes calldata allowlistProof_,
        bytes calldata permit2Data_
    ) external override nonReentrant returns (uint64) {
        // Lot ID must be valid and the lot must be active
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotConcluded(lotId_);
        _revertIfLotSettled(lotId_);

        // Load routing data for the lot
        Routing memory routing = lotRouting[lotId_];

        // Determine if the bidder is authorized to bid
        if (!_isAllowed(routing.allowlist, lotId_, msg.sender, allowlistProof_)) {
            revert NotPermitted(msg.sender);
        }

        // Check that the amount is greater than the minimum quote token bid size implied by the minimum price and minimum base token bid size
        if (
            amount_
                < (
                    (uint256(lotData[lotId_].minBidSize) * uint256(lotData[lotId_].minimumPrice))
                        / 10 ** lotData[lotId_].baseTokenDecimals
                )
        ) revert AmountLessThanMinimum();

        // Check that the public key for the shared secret is a valid point on the alt_bn128 curve
        if (!ECIES.isOnBn128(bidPubKey_)) revert Bid_InvalidPublicKey();

        // Store bid data
        uint64 bidId = bidData[lotId_].nextBidId++;
        Bid storage userBid = bids[lotId_][bidId];
        userBid.bidder = msg.sender;
        userBid.amount = amount_;
        userBid.referrer = referrer_;
        userBid.status = BidStatus.Submitted;

        // Store encrypted amount out
        encryptedBids[lotId_][bidId] =
            EncryptedBid({encryptedAmountOut: encryptedAmountOut_, bidPubKey: bidPubKey_});

        // Push bid ID to list of bids to decrypt
        bidData[lotId_].bidIds.push(bidId);

        // Transfer the quote token from the bidder
        _collectPayment(
            lotId_,
            amount_,
            routing.quoteToken,
            routing.hooks,
            Transfer.decodePermit2Approval(permit2Data_)
        );

        // Emit event
        emit BidSubmitted(lotId_, bidId, msg.sender, amount_);

        return bidId;
    }

    /// @inheritdoc Router
    /// @dev        This function reverts if:
    ///             - the lot ID is invalid
    ///             - the auction module reverts when cancelling the bid
    ///             - re-entrancy is detected
    function refundBid(uint96 lotId_, uint64 bidId_) external override nonReentrant {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);
        _revertIfNotBidOwner(lotId_, bidId_, msg.sender);
        _revertIfBidClaimed(lotId_, bidId_);
        _revertIfLotConcluded(lotId_);

        // Bid must be in Submitted state
        Bid storage _bid = bids[lotId_][bidId_];

        // TODO probably covered by the above
        if (_bid.status != BidStatus.Submitted) revert Bid_WrongState();

        // Set bid status to refunded
        _bid.status = BidStatus.Refunded;

        // Remove bid from list of bids to decrypt
        uint64[] storage bidIds = bidData[lotId_].bidIds;
        uint256 len = bidIds.length;
        for (uint256 i; i < len; i++) {
            if (bidIds[i] == bidId_) {
                bidIds[i] = bidIds[len - 1];
                bidIds.pop();
                break;
            }
        }

        // Transfer the quote token to the bidder
        // The ownership of the bid has already been verified by the auction module
        Transfer.transfer(lotRouting[lotId_].quoteToken, msg.sender, _bid.amount, false);

        // Emit event
        emit RefundBid(lotId_, bidId_, msg.sender);
    }

    /// @notice     Applies mulDivUp to uint96 values, and checks that the result is within the uint96 range
    function _mulDivUp(uint96 mul1_, uint96 mul2_, uint96 div_) internal pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivUp(mul1_, mul2_, div_);
        if (product > type(uint96).max) revert Overflow();

        return uint96(product);
    }

    /// @inheritdoc Router
    /// @dev        This function handles the following:
    ///             - Settles the auction on the auction module
    ///             - Calculates the payout amount, taking partial fill into consideration
    ///             - Calculates the fees taken on the quote token
    ///             - Collects the payout from the auction owner (if necessary)
    ///             - Sends the payout to each bidder
    ///             - Sends the payment to the auction owner
    ///             - Sends the refund to the bidder if the last bid was a partial fill
    ///             - Refunds any unused base token to the auction owner
    ///
    ///             This function reverts if:
    ///             - the lot ID is invalid
    ///             - the lot state is invalid
    ///             - transferring the quote token to the auction owner fails
    ///             - sending the payout to each bidder fails
    ///             - re-entrancy is detected
    function settle(uint96 lotId_) external override nonReentrant {
        // Validation
        // Lot ID must be valid. Lot must be concluded, but not settled
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotActive(lotId_);
        _revertIfLotSettled(lotId_);

        // Settle the auction
        // Check that auction is in the right state for settlement
        if (lotData[lotId_].status != AuctionStatus.Decrypted) revert Auction_WrongState();

        // Calculate marginal price and number of winning bids
        // Cache capacity and scaling values
        // Capacity is always in base token units for this auction type
        uint96 capacity = lotData[lotId_].capacity;
        uint96 baseScale = uint96(10 ** lotData[lotId_].baseTokenDecimals); // We know this is true, since baseTokenDecimals is 6-18
        uint96 minimumPrice = lotData[lotId_].minimumPrice;

        // Iterate over bid queue (sorted in descending price) to calculate the marginal clearing price of the auction
        uint96 marginalPrice;
        uint96 totalAmountIn;
        uint96 capacityExpended;
        uint64 partialFillBidId;
        {
            Queue storage queue = decryptedBids[lotId_];
            uint256 numBids = queue.getNumBids();
            uint96 lastPrice;
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
                uint96 price = _mulDivUp(qBid.amountIn, baseScale, qBid.minAmountOut);

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
                capacityExpended = _mulDivUp(totalAmountIn, baseScale, price);

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
        lotData[lotId_].status = AuctionStatus.Settled;
        // Auction cannot be settled if the total filled is less than the minimum filled
        // or if the marginal price is less than the minimum price
        if (capacityExpended >= lotData[lotId_].minFilled && marginalPrice >= minimumPrice) {
            // Auction can be settled at the marginal price if we reach this point
            bidData[lotId_].marginalPrice = marginalPrice;

            Routing storage routing = lotRouting[lotId_];

            // If there is a partially filled bid, send proceeds and refund to that bidder now
            if (partialFillBidId != 0) {
                // Load routing and bid data
                Bid storage _bid = bids[lotId_][partialFillBidId];

                // Calculate the payout and refund amounts
                uint96 fullFill = _mulDivUp(_bid.amount, baseScale, marginalPrice);
                uint96 overflow = capacityExpended - capacity;
                uint96 payout = fullFill - overflow;
                uint96 refundAmount = _mulDivUp(_bid.amount, overflow, fullFill);

                // Reduce the total amount in by the refund amount
                totalAmountIn -= refundAmount;

                // Set bid as claimed
                _bid.status = BidStatus.Claimed;

                // Allocate quote and protocol fees for bid
                _allocateQuoteFees(
                    _bid.referrer, routing.owner, routing.quoteToken, _bid.amount - refundAmount
                );

                // Send refund and payout to the bidder
                Transfer.transfer(routing.quoteToken, _bid.bidder, refundAmount, false);
                _sendPayout(lotId_, _bid.bidder, payout, routing);
            }

            // Calculate the referrer and protocol fees for the amount in
            // Fees are not allocated until the user claims their payout so that we don't have to iterate through them here
            // If a referrer is not set, that portion of the fee defaults to the protocol
            uint96 totalAmountInLessFees;
            {
                (, uint96 toProtocol) = calculateQuoteFees(false, totalAmountIn);
                totalAmountInLessFees = totalAmountIn - toProtocol;
            }

            // Send payment in bulk to auction owner
            _sendPayment(routing.owner, totalAmountInLessFees, routing.quoteToken, routing.hooks);

            // If capacity expended is less than the total capacity, refund the remaining capacity to the seller
            if (capacityExpended < capacity) {
                Transfer.transfer(
                    routing.baseToken, routing.owner, capacity - capacityExpended, false
                );
            }

            // Calculate and send curator fee to curator (if applicable)
            uint96 curatorFee = _calculatePayoutFees(
                routing.curator, capacityExpended > capacity ? capacity : capacityExpended
            );
            if (curatorFee > 0) _sendPayout(lotId_, routing.curator, curatorFee, routing);

            // Refund the remaining curator fees to the owner
            // TODO can be combined with the above transfer
            if (routing.curated == true && curatorFee < routing.curatorFee) {
                Transfer.transfer(
                    routing.baseToken, routing.owner, routing.curatorFee - curatorFee, false
                );
            }
        } else {
            // Auction cannot be settled if we reach this point
            // Marginal price is not set for the auction so the system knows all bids should be refunded

            uint96 refundAmount = capacity;

            if (lotRouting[lotId_].curated == true) {
                refundAmount += lotRouting[lotId_].curatorFee;
            }

            // Refund the capacity to the seller, no fees are taken
            Transfer.transfer(
                lotRouting[lotId_].baseToken, lotRouting[lotId_].owner, refundAmount, false
            );
        }

        // Emit event
        emit Settle(lotId_);
    }

    /// @inheritdoc Router
    function claim(uint96 lotId_, uint64 bidId_) external override nonReentrant {
        // Validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotNotSettled(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);
        _revertIfBidClaimed(lotId_, bidId_);

        // Get the bid and compare to settled auction price
        Bid storage _bid = bids[lotId_][bidId_];
        BidStatus status = _bid.status;

        // Set bid status to claimed
        bids[lotId_][bidId_].status = BidStatus.Claimed;

        // If the bid was not decrypted, refund the bid amount
        if (status == BidStatus.Submitted) {
            Transfer.transfer(lotRouting[lotId_].quoteToken, _bid.bidder, _bid.amount, false);
            return;
        }

        // Calculate the bid price
        uint96 bidPrice = _mulDivUp(
            _bid.amount, uint96(10) ** lotData[lotId_].baseTokenDecimals, _bid.minAmountOut
        );
        uint96 marginalPrice = bidData[lotId_].marginalPrice;

        // If the bid price is greater than or equal the settled price, then payout expected amount
        // We don't have to worry about partial fills here because the bid which is partially filled is handled during settlement
        // Else the bid price is less than the settled price, so refund the bid amount
        uint96 quoteAmount;
        uint96 payoutAmount;
        if (marginalPrice > 0 && bidPrice >= marginalPrice) {
            // Allocate quote token fees
            _allocateQuoteFees(
                _bid.referrer, lotRouting[lotId_].owner, lotRouting[lotId_].quoteToken, _bid.amount
            );

            // Calculate payout using marginal price
            payoutAmount = _mulDivUp(
                _bid.amount, uint96(10) ** lotData[lotId_].baseTokenDecimals, marginalPrice
            );

            // Transfer payout to the bidder
            _sendPayout(lotId_, _bid.bidder, payoutAmount, lotRouting[lotId_]);
        } else {
            // Refund the bid amount to the bidder
            quoteAmount = _bid.amount;
            Transfer.transfer(lotRouting[lotId_].quoteToken, _bid.bidder, quoteAmount, false);
        }

        // Emit event
        emit Claimed(lotId_, bidId_, quoteAmount, payoutAmount);
    }

    // =========== DECRYPTION =========== //

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
        if (bidData[lotId_].privateKey != 0) revert Auction_WrongState();

        // Check that the private key is valid for the public key
        // We assume that all public keys are derived from the same generator: (1, 2)
        Point memory calcPubKey = ECIES.calcPubKey(Point(1, 2), privateKey_);
        Point memory pubKey = bidData[lotId_].publicKey;
        if (calcPubKey.x != pubKey.x || calcPubKey.y != pubKey.y) revert Bid_InvalidPrivateKey();

        // Store the private key
        bidData[lotId_].privateKey = privateKey_;

        // Decrypt and sort bids
        _decryptAndSortBids(lotId_, num_);
    }

    /// @notice         Decrypts a batch of bids and sorts them by price in descending order
    ///                 This function expects a third-party with access to the lot's private key
    ///                 to decrypt the bids off-chain (after calling `getNextBidsToDecrypt()`) and
    ///                 submit them on-chain.
    /// @dev            Anyone can call this function, provided they have access to the private key to decrypt the bids.
    ///
    ///                 This function handles the following:
    ///                 - Performs validation
    ///                 - Iterates over the decrypted bids:
    ///                     - Re-encrypts the decrypted bid to confirm that it matches the stored encrypted bid
    ///                     - If the bid meets the minimum bid size, stores the decrypted bid in the sorted bid queue and updates the status.
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
    /// @param          num_            The number of bids to decrypt. Reduced to the number remaining if greater.
    function decryptAndSortBids(uint96 lotId_, uint64 num_) external {
        // Check that lotId is valid
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotActive(lotId_);

        // Revert if already decrypted or if the private key has not been provided
        if (lotData[lotId_].status != AuctionStatus.Created || bidData[lotId_].privateKey == 0) {
            revert Auction_WrongState();
        }

        // Decrypt and sort bids
        _decryptAndSortBids(lotId_, num_);
    }

    function _decryptAndSortBids(uint96 lotId_, uint64 num_) internal {
        // Load next decrypt index and private key
        BidData storage lotBidData = bidData[lotId_];
        uint64 nextDecryptIndex = lotBidData.nextDecryptIndex;
        uint256 privateKey = lotBidData.privateKey;

        // Check that the number of decrypts is less than or equal to the number of bids remaining to be decrypted
        // If so, reduce to the number remaining
        uint64[] storage bidIds = bidData[lotId_].bidIds;
        if (num_ > bidIds.length - nextDecryptIndex) {
            num_ = uint64(bidIds.length) - nextDecryptIndex;
        }

        // Iterate over the provided number of bids, decrypt them, and then store them in the sorted bid queue
        uint96 minBidSize = lotData[lotId_].minBidSize;
        for (uint64 i; i < num_; i++) {
            // Load encrypted bid
            uint64 bidId = bidIds[nextDecryptIndex + i];

            // Decrypt the bid
            uint256 result = _decrypt(lotId_, bidId, privateKey);
            // We skip the bid if the decrypted amount out overflows the uint96 type
            // No valid bid should expect more than 7.9 * 10^28 (79 trillion tokens if 18 decimals)
            if (result > type(uint96).max) continue;
            uint96 amountOut = uint96(result);

            // Only store the decrypt if the amount out is greater than or equal to the minimum bid size
            Bid storage _bid = bids[lotId_][bidId];
            if (amountOut >= minBidSize) {
                // Store the decrypt in the sorted bid queue
                decryptedBids[lotId_].insert(bidId, _bid.amount, amountOut);
            }

            // Set bid status to decrypted and the min amount out
            _bid.status = BidStatus.Decrypted;
            _bid.minAmountOut = amountOut;

            // Emit event
            emit BidDecrypted(lotId_, bidId, _bid.amount, amountOut);
        }

        // Increment next decrypt index
        bidData[lotId_].nextDecryptIndex += num_;

        // If all bids have been decrypted, set auction status to decrypted
        if (bidData[lotId_].nextDecryptIndex == bidIds.length) {
            lotData[lotId_].status = AuctionStatus.Decrypted;
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
        Bid storage _bid = bids[lotId_][bidId_];
        uint256 message = ECIES.decrypt(
            encryptedBid.encryptedAmountOut,
            encryptedBid.bidPubKey,
            privateKey_,
            uint256(keccak256(abi.encodePacked(lotId_, _bid.bidder, _bid.amount)))
        );

        // Convert the message into the amount out
        // We don't need larger than 16 bytes for a message
        // To avoid attacks that check for leading zero values, encrypted bids should use a 128-bit random number
        // as a seed to randomize the message. The seed should be the first 16 bytes.
        // We subtract the actual value from the random number to get a subtracted value which is the amount out
        // relative to the random number.
        // After decryption, we can combine them again and get the amount out
        bytes memory messageBytes = abi.encodePacked(message);

        uint128 rand;
        uint128 subtracted;
        assembly {
            rand := mload(add(messageBytes, 16))
            subtracted := mload(add(messageBytes, 32))
        }

        // We want to allow underflow here
        unchecked {
            amountOut = uint256(rand - subtracted);
        }
    }

    // ========== CURATION ========== //

    /// @notice     Accept curation request for a lot.
    /// @notice     Access controlled. Must be proposed curator for lot.
    /// @dev        This function reverts if:
    ///             - the lot ID is invalid
    ///             - the caller is not the proposed curator
    ///             - the auction has ended or been cancelled
    ///             - the curator fee is not set
    ///             - the auction is prefunded and the fee cannot be collected
    ///             - re-entrancy is detected
    ///
    /// @param     lotId_       Lot ID
    function curate(uint96 lotId_) external nonReentrant {
        // Validation
        // Lot ID must be valid and the lot must not have concluded yet
        _revertIfLotInvalid(lotId_);
        _revertIfLotConcluded(lotId_);

        Routing storage routing = lotRouting[lotId_];

        // Check that the caller is the proposed curator
        if (msg.sender != routing.curator) revert NotPermitted(msg.sender);

        // Check that the curator has not already approved the auction
        if (routing.curated) revert Auction_WrongState();

        // Check that the curator fee is set
        if (fees.curator[msg.sender] == 0) revert InvalidFee();

        // Set the curator as approved
        routing.curated = true;

        // Auction must be prefunded, so we transfer the curator fee to the contract from the owner
        // Calculate the fee amount based on the remaining capacity (must be in base token if auction is pre-funded)
        uint96 fee = _calculatePayoutFees(msg.sender, lotData[lotId_].capacity);
        routing.curatorFee = fee;

        // Don't need to check for fee on transfer here because it was checked on auction creation
        Transfer.transferFrom(routing.baseToken, routing.owner, address(this), fee, false);

        // Emit event that the lot is curated by the proposed curator
        emit Curated(lotId_, msg.sender);
    }

    // ========== TOKEN TRANSFERS ========== //

    /// @notice     Collects payment of the quote token from the user
    /// @dev        This function handles the following:
    ///             1. Calls the pre hook on the hooks contract (if provided)
    ///             2. Transfers the quote token from the user
    ///             2a. Uses Permit2 to transfer if approval signature is provided
    ///             2b. Otherwise uses a standard ERC20 transfer
    ///
    ///             This function reverts if:
    ///             - The Permit2 approval is invalid
    ///             - The caller does not have sufficient balance of the quote token
    ///             - Approval has not been granted to transfer the quote token
    ///             - The quote token transfer fails
    ///             - Transferring the quote token would result in a lesser amount being received
    ///             - The pre-hook reverts
    ///             - TODO: The pre-hook invariant is violated
    ///
    /// @param      lotId_              Lot ID
    /// @param      amount_             Amount of quoteToken to collect (in native decimals)
    /// @param      quoteToken_         Quote token to collect
    /// @param      hooks_              Hooks contract to call (optional)
    /// @param      permit2Approval_    Permit2 approval data (optional)
    function _collectPayment(
        uint96 lotId_,
        uint256 amount_,
        ERC20 quoteToken_,
        IHooks hooks_,
        Transfer.Permit2Approval memory permit2Approval_
    ) internal {
        // Call pre hook on hooks contract if provided
        if (address(hooks_) != address(0)) {
            hooks_.pre(lotId_, amount_);
        }

        Transfer.permit2OrTransferFrom(
            quoteToken_, _PERMIT2, msg.sender, address(this), amount_, permit2Approval_, true
        );
    }

    /// @notice     Sends payment of the quote token to the auction owner
    /// @dev        This function handles the following:
    ///             1. Sends the payment amount to the auction owner or hook (if provided)
    ///             This function assumes:
    ///             - The quote token has already been transferred to this contract
    ///             - The quote token is supported (e.g. not fee-on-transfer)
    ///
    ///             This function reverts if:
    ///             - The transfer fails
    ///
    /// @param      lotOwner_       Owner of the lot
    /// @param      amount_         Amount of quoteToken to send (in native decimals)
    /// @param      quoteToken_     Quote token to send
    /// @param      hooks_          Hooks contract to call (optional)
    function _sendPayment(
        address lotOwner_,
        uint256 amount_,
        ERC20 quoteToken_,
        IHooks hooks_
    ) internal {
        Transfer.transfer(
            quoteToken_, address(hooks_) == address(0) ? lotOwner_ : address(hooks_), amount_, false
        );
    }

    /// @notice     Sends the payout token to the recipient
    /// @dev        This function handles the following:
    ///             1. Sends the payout token from the router to the recipient
    ///             1a. If the lot is a derivative, mints the derivative token to the recipient
    ///             2. Calls the post hook on the hooks contract (if provided)
    ///
    ///             This function assumes that:
    ///             - The payout token has already been transferred to this contract
    ///             - The payout token is supported (e.g. not fee-on-transfer)
    ///
    ///             This function reverts if:
    ///             - The payout token transfer fails
    ///             - The payout token transfer would result in a lesser amount being received
    ///             - The post-hook reverts
    ///             - The post-hook invariant is violated
    ///
    /// @param      lotId_          Lot ID
    /// @param      recipient_      Address to receive payout
    /// @param      payoutAmount_   Amount of payoutToken to send (in native decimals)
    /// @param      routingParams_  Routing parameters for the lot
    function _sendPayout(
        uint96 lotId_,
        address recipient_,
        uint256 payoutAmount_,
        Routing memory routingParams_
    ) internal {
        Veecode derivativeReference = routingParams_.derivativeReference;
        ERC20 baseToken = routingParams_.baseToken;

        // If no derivative, then the payout is sent directly to the recipient
        if (fromVeecode(derivativeReference) == bytes7("")) {
            Transfer.transfer(baseToken, recipient_, payoutAmount_, true);
        }
        // Otherwise, send parameters and payout to the derivative to mint to recipient
        else {
            // Get the module for the derivative type
            // We assume that the module type has been checked when the lot was created
            DerivativeModule module = DerivativeModule(_getModuleIfInstalled(derivativeReference));

            // Approve the module to transfer payout tokens when minting
            Transfer.approve(baseToken, address(module), payoutAmount_);

            // Call the module to mint derivative tokens to the recipient
            module.mint(
                recipient_,
                address(baseToken),
                routingParams_.derivativeParams,
                payoutAmount_,
                routingParams_.wrapDerivative
            );
        }

        // Call post hook on hooks contract if provided
        if (address(routingParams_.hooks) != address(0)) {
            routingParams_.hooks.post(lotId_, payoutAmount_);
        }
    }

    // ========== FEE FUNCTIONS ========== //

    function _allocateQuoteFees(
        address referrer_,
        address owner_,
        ERC20 quoteToken_,
        uint96 amount_
    ) internal returns (uint96 toReferrer, uint96 toProtocol) {
        // Calculate fees for purchase
        (toReferrer, toProtocol) =
            calculateQuoteFees(referrer_ != address(0) && referrer_ != owner_, amount_);

        // Update fee balances if non-zero
        if (toReferrer > 0) rewards[referrer_][quoteToken_] += toReferrer;
        if (toProtocol > 0) rewards[_protocol][quoteToken_] += toProtocol;

        return (toReferrer, toProtocol);
    }

    // ========== MODIFIERS ========== //

    /// @notice     Checks that `lotId_` is valid
    /// @dev        Should revert if the lot ID is invalid
    ///             Inheriting contracts can override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotInvalid(uint96 lotId_) internal view virtual {
        if (lotId_ >= lotCounter) revert Auction_InvalidId(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` has not started
    /// @dev        Should revert if the lot has not started
    function _revertIfBeforeLotStart(uint96 lotId_) internal view virtual {
        if (lotData[lotId_].start > uint48(block.timestamp)) revert Auction_MarketNotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` has started
    /// @dev        Should revert if the lot has started
    function _revertIfLotStarted(uint96 lotId_) internal view virtual {
        if (lotData[lotId_].start <= uint48(block.timestamp)) revert Auction_MarketActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` has not concluded
    /// @dev        Should revert if the lot has concluded
    function _revertIfLotConcluded(uint96 lotId_) internal view virtual {
        // Beyond the conclusion time
        if (lotData[lotId_].conclusion < uint48(block.timestamp)) {
            revert Auction_MarketNotActive(lotId_);
        }

        // Capacity is sold-out, or cancelled
        if (lotData[lotId_].capacity == 0) revert Auction_MarketNotActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` is active
    /// @dev        Should revert if the lot is active
    ///             Inheriting contracts can override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotActive(uint96 lotId_) internal view virtual {
        if (
            lotData[lotId_].status == AuctionStatus.Created
                && lotData[lotId_].start <= block.timestamp
                && lotData[lotId_].conclusion > block.timestamp
        ) revert Auction_MarketActive(lotId_);
    }

    /// @notice     Checks that the lot represented by `lotId_` is active
    /// @dev        Should revert if the lot is not active
    ///             Inheriting contracts can override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotInactive(uint96 lotId_) internal view {
        // Check that bids are allowed to be submitted for the lot
        if (
            lotData[lotId_].status != AuctionStatus.Created
                || block.timestamp < lotData[lotId_].start
                || block.timestamp >= lotData[lotId_].conclusion
        ) revert Auction_MarketNotActive(lotId_);
    }

    /// @notice     Reverts if the lot has already been decrypted
    function _revertIfLotDecrypted(uint96 lotId_) internal view {
        // Check that bids are allowed to be submitted for the lot
        if (lotData[lotId_].status == AuctionStatus.Decrypted) revert Auction_WrongState();
    }

    /// @notice     Checks that the lot represented by `lotId_` is not settled
    /// @dev        Should revert if the lot is settled
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotSettled(uint96 lotId_) internal view {
        // Auction must not be settled
        if (lotData[lotId_].status == AuctionStatus.Settled) {
            revert Auction_WrongState();
        }
    }

    /// @notice     Checks that the lot represented by `lotId_` is settled
    /// @dev        Should revert if the lot is not settled
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotNotSettled(uint96 lotId_) internal view {
        // Auction must be settled
        if (lotData[lotId_].status != AuctionStatus.Settled) {
            revert Auction_WrongState();
        }
    }

    /// @notice     Checks that the lot and bid combination is valid
    /// @dev        Should revert if the bid is invalid
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    /// @param      bidId_  The bid ID
    function _revertIfBidInvalid(uint96 lotId_, uint64 bidId_) internal view {
        // Bid ID must be less than number of bids for lot
        if (bidId_ >= bidData[lotId_].nextBidId) revert Bid_InvalidId(lotId_, bidId_);

        // Bid should have a bidder
        if (bids[lotId_][bidId_].bidder == address(0)) revert Bid_InvalidId(lotId_, bidId_);
    }

    /// @notice     Checks that `caller_` is the bid owner
    /// @dev        Should revert if `caller_` is not the bid owner
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    /// @param      caller_     The caller
    function _revertIfNotBidOwner(uint96 lotId_, uint64 bidId_, address caller_) internal view {
        // Check that sender is the bidder
        if (caller_ != bids[lotId_][bidId_].bidder) revert NotPermitted(caller_);
    }

    /// @notice     Checks that the bid is not refunded/claimed already
    /// @dev        Should revert if the bid is claimed
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    function _revertIfBidClaimed(uint96 lotId_, uint64 bidId_) internal view {
        // Bid must not be cancelled
        if (bids[lotId_][bidId_].status == BidStatus.Claimed) {
            revert Bid_AlreadyClaimed();
        }
    }
}
