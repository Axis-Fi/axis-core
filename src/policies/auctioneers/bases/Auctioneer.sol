/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";

import {IAuctioneer} from "src/interfaces/IAuctioneer.sol";
import {ITeller} from "src/interfaces/ITeller.sol";
import {IAggregator} from "src/interfaces/IAggregator.sol";

import {TransferHelper} from "src/lib/TransferHelper.sol";
import {FullMath} from "src/lib/FullMath.sol";

/// @title Auctioneer
/// @notice Bond Auctioneer Base Contract
/// @dev Bond Protocol is a system to create markets for any token pair.
///      Bond issuers create BondMarkets that pay out a Payout Token in exchange
///      for deposited Quote Tokens. Users can purchase future-dated Payout Tokens
///      with Quote Tokens at the current market price and receive Bond Tokens to
///      represent their position while their bond vests. Once the Bond Tokens vest,
///      they can redeem it for the Quote Tokens. Alternatively, markets can be
///      instant swap and payouts are made immediately to the user.
///
/// @dev An Auctioneer contract allows users to create and manage bond markets.
///      All bond pricing logic and market data is stored in the Auctioneer.
///      An Auctioneer is dependent on a Teller to serve external users and
///      an Aggregator to register new markets.
///
/// @author Oighty
abstract contract Auctioneer is IAuctioneer, Auth {
    using TransferHelper for ERC20;
    using FullMath for uint256;

    /* ========== ERRORS ========== */

    error Auctioneer_OnlyMarketOwner();
    error Auctioneer_MarketNotActive();
    error Auctioneer_AmountLessThanMinimum();
    error Auctioneer_NotEnoughCapacity();
    error Auctioneer_InvalidParams();
    error Auctioneer_NotAuthorized();
    error Auctioneer_NewMarketsNotAllowed();

    /* ========== EVENTS ========== */

    event MarketCreated(
        uint256 indexed id,
        address indexed payoutToken,
        address indexed quoteToken
    );
    event MarketClosed(uint256 indexed id);

    /* ========== STATE ========== */

    /// @notice Whether or not the auctioneer allows new markets to be created
    /// @dev    Changing to false will sunset the auctioneer after all active markets end
    bool public allowNewMarkets;

    /// @notice Minimum market duration in seconds
    uint48 public minMarketDuration;

    // Aggregator contract to register markets and check teller validity
    IAggregator internal immutable _aggregator;

    // 1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint48 internal constant ONE_HUNDRED_PERCENT = 1e5;

    /// @notice Information pertaining to bond markets
    mapping(uint256 id => CoreData core) public coreData;

    /// @notice New address to designate as market owner. They must accept ownership to transfer permissions.
    mapping(uint256 => address) public newOwners;

    constructor(
        IAggregator aggregator_,
        address guardian_,
        Authority authority_
    ) Auth(address(0), authority_) {
        _aggregator = aggregator_;
        minMarketDuration = 1 days;
        allowNewMarkets = true;
    }

    /* ========== MARKET FUNCTIONS ========== */

    /// @inheritdoc IAuctioneer
    function createMarket(MarketParams calldata params_) external returns (uint256) {
        // Check that the auctioneer is allowing new markets to be created
        if (!allowNewMarkets) revert Auctioneer_NewMarketsNotAllowed();

        // Start time must be zero or in the future
        if (params_.start > 0 && params_.start < uint48(block.timestamp))
            revert Auctioneer_InvalidParams();

        // Duration must be at least min duration
        if (params_.duration < minMarketDuration) revert Auctioneer_InvalidParams();

        // Ensure token decimals are in-bounds
        {
            uint8 payoutTokenDecimals = params_.payoutToken.decimals();
            uint8 quoteTokenDecimals = params_.quoteToken.decimals();

            if (payoutTokenDecimals < 6 || payoutTokenDecimals > 18)
                revert Auctioneer_InvalidParams();
            if (quoteTokenDecimals < 6 || quoteTokenDecimals > 18)
                revert Auctioneer_InvalidParams();
        }

        // Validate teller is approved
        if (!_aggregator.isTeller(address(params_.teller))) revert Auctioneer_InvalidParams();

        // Register new market on aggregator and get market id
        uint256 id = _aggregator.registerMarket(params_.payoutToken, params_.quoteToken);

        // Create core market data
        CoreData memory core;
        core.owner = msg.sender;
        core.payoutToken = params_.payoutToken;
        core.quoteToken = params_.quoteToken;
        core.callbackAddr = params_.callbackAddr;
        core.teller = params_.teller;
        core.capacityInQuote = params_.capacityInQuote;
        core.capacity = params_.capacity;
        core.start = params_.start == 0 ? uint48(block.timestamp) : params_.start;
        core.conclusion = core.start + params_.duration;

        // Store core market data
        coreData[id] = core;

        // Register market on teller and validate teller params
        params_.teller.registerMarket(
            id,
            core,
            params_.tellerParams,
            params_.allowlist,
            params_.allowlistParams
        );

        // Call internal createMarket function to store implementation-specific data
        _createMarket(id, core, params_.auctionParams);

        emit MarketCreated(id, address(params_.payoutToken), address(params_.quoteToken));

        return id;
    }

    /// @dev implementation-specific market creation logic can be inserted by overriding this function
    function _createMarket(
        uint256 id_,
        CoreData memory core_,
        bytes calldata params_
    ) internal returns (uint256);

    /// @inheritdoc IAuctioneer
    function pushOwnership(uint256 id_, address newOwner_) external override {
        if (msg.sender != coreData[id_].owner) revert Auctioneer_OnlyMarketOwner();
        newOwners[id_] = newOwner_;
    }

    /// @inheritdoc IAuctioneer
    function pullOwnership(uint256 id_) external override {
        if (msg.sender != newOwners[id_]) revert Auctioneer_NotAuthorized();
        coreData[id_].owner = newOwners[id_];
    }

    /// @inheritdoc IAuctioneer
    function setMinMarketDuration(uint48 duration_) external override requiresAuth {
        // Restricted to authorized addresses

        // Require minimum market duration to be at least 1 day
        if (duration_ < 1 days) revert Auctioneer_InvalidParams();

        // Validate implementation-specific restrictions on market duration
        _setMinMarketDuration(duration_);

        minMarketDuration = duration_;
    }

    /// @dev implementation-specific duration logic can be inserted by overriding this function
    function _setMinMarketDuration(uint48 duration_) internal virtual {}

    /// @inheritdoc IAuctioneer
    function setAllowNewMarkets(bool status_) external override requiresAuth {
        // Restricted to authorized addresses
        allowNewMarkets = status_;
    }

    /// @inheritdoc IAuctioneer
    function closeMarket(uint256 id_) external override {
        CoreData memory core = coreData[id_];
        if (msg.sender != core.owner) revert Auctioneer_OnlyMarketOwner();
        core.conclusion = uint48(block.timestamp);
        core.capacity = 0;

        emit MarketClosed(id_);
    }

    /* ========== TELLER FUNCTIONS ========== */

    /// @inheritdoc IAuctioneer
    function purchase(
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_
    ) external returns (uint256 payout) {
        CoreData storage core = coreData[id_];

        // Check that sender is configured teller
        if (msg.sender != address(core.teller)) revert Auctioneer_NotAuthorized();

        // Check if market is live, if not revert
        if (!isLive(id_)) revert Auctioneer_MarketNotActive();

        // Get payout from implementation-specific auction logic
        payout = _purchase(id_, amount_);

        // Check that payout is at least minimum amount out
        if (payout < minAmountOut_) revert Auctioneer_AmountLessThanMinimum();

        // Update Capacity

        // Capacity is either the number of payout tokens that the market can sell
        // (if capacity in quote is false),
        //
        // or the number of quote tokens that the market can buy
        // (if capacity in quote is true)

        // If amount/payout is greater than capacity remaining, revert
        if (core.capacityInQuote ? amount_ > core.capacity : payout > core.capacity)
            revert Auctioneer_NotEnoughCapacity();
        // Capacity is decreased by the deposited or paid amount
        core.capacity -= core.capacityInQuote ? amount_ : payout;

        // Markets keep track of how many quote tokens have been
        // purchased, and how many payout tokens have been sold
        core.purchased += amount_;
        core.sold += payout;
    }

    /// @dev implementation-specific purchase logic can be inserted by overriding this function
    function _purchase(
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_
    ) internal virtual returns (uint256);

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc IAuctioneer
    function getMarketInfoForPurchase(
        uint256 id_
    )
        external
        view
        returns (address owner, address callbackAddr, ERC20 payoutToken, ERC20 quoteToken)
    {
        CoreData memory core = coreData[id_];
        return (core.owner, core.callbackAddr, core.payoutToken, core.quoteToken);
    }

    /// @inheritdoc IAuctioneer
    function payoutFor(
        uint256 id_,
        uint256 amount_,
        address referrer_
    ) public view override returns (uint256) {
        CoreData memory core = coreData[id_];

        // Calculate the payout for the given amount of tokens
        uint256 fee = amount_.mulDiv(core.teller.getFee(referrer_), ONE_HUNDRED_PERCENT);

        // Get payout for from implementation-specific auction logic
        // If the amount is greater than an implementation-specific maximum, this function should revert internally
        return _payoutFor(id_, amount_ - fee);
    }

    function _payoutFor(uint256 id_, uint256 amount_) internal view virtual returns (uint256);

    /// @inheritdoc IAuctioneer
    function maxAmountAccepted(
        uint256 id_,
        address referrer_
    ) external view virtual returns (uint256);

    /// @inheritdoc IAuctioneer
    function isLive(uint256 id_) public view override returns (bool) {
        CoreData memory core = coreData[id_];
        return (core.capacity != 0 &&
            core.conclusion > uint48(block.timestamp) &&
            core.start <= uint48(block.timestamp));
    }

    /// @inheritdoc IAuctioneer
    function ownerOf(uint256 id_) external view override returns (address) {
        return coreData[id_].owner;
    }

    /// @inheritdoc IAuctioneer
    function getTeller(uint256 id_) external view override returns (ITeller) {
        return coreData[id_].teller;
    }

    /// @inheritdoc IAuctioneer
    function getAggregator() external view override returns (IAggregator) {
        return _aggregator;
    }

    /// @inheritdoc IAuctioneer
    function currentCapacity(uint256 id_) external view override returns (uint256) {
        return coreData[id_].capacity;
    }
}
