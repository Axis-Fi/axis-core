/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "src/monolithic/modules/Auction.sol";

abstract contract Auctioneer is WithModules {

    // ========= DATA STRUCTURES ========== //

    /// @notice Auction routing information for a lot
    struct Routing {
        Keycode auctionType; // auction type, represented by the Keycode for the auction submodule
        address owner; // market owner. sends payout tokens, receives quote tokens
        ERC20 payoutToken; // TODO think about a better way to describe quote and payout assets
        ERC20 quoteToken; // token to accept as payment
        IHooks hooks; // address to call for any hooks to be executed on a purchase. Must implement IHooks.
        IAllowlist allowlist; // (optional) contract that implements an allowlist for the market, based on IAllowlist
        Keycode derivativeType; // (optional) derivative type, represented by the Keycode for the derivative submodule. If not set, no derivative will be created.
        bytes derivativeParams; // (optional) abi-encoded data to be used to create payout derivatives on a purchase
        bool wrapDerivative; // (optional) whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format.
        Keycode condenserType; // (optional) condenser type, represented by the Keycode for the condenser submodule. If not set, no condenser will be used.
    }

    struct RoutingParams {
        Keycode auctionType;
        ERC20 payoutToken;
        ERC20 quoteToken;
        IHooks hooks;
        IAllowlist allowlist;
        bytes allowlistParams;
        bytes payoutData;
        Keycode derivativeType; // (optional) derivative type, represented by the Keycode for the derivative submodule. If not set, no derivative will be created.
        bytes derivativeParams; // (optional) data to be used to create payout derivatives on a purchase
        Keycode condenserType; // (optional) condenser type, represented by the Keycode for the condenser submodule. If not set, no condenser will be used.
    }

    // ========= STATE ========== //

    // 1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint48 internal constant ONE_HUNDRED_PERCENT = 1e5;

    /// @notice Counter for auction lots
    uint256 public lotCounter;

    /// @notice Designates whether an auction type is sunset on this contract
    /// @dev We can remove Keycodes from the module to completely remove them,
    ///      However, that would brick any existing auctions of that type.
    ///      Therefore, we can sunset them instead, which will prevent new auctions.
    ///      After they have all ended, then we can remove them.
    mapping(Keycode auctionType => bool) public typeSunset;

    /// @notice Mapping of lot IDs to their auction type (represented by the Keycode for the auction submodule)
    mapping(uint256 lotId => Routing) public lotRouting;

    // ========== AUCTION EXECUTION ========== //

    function _getModuleForId(uint256 id_) internal view returns (AuctionModule) {
        // Confirm lot ID is valid
        if (id_ >= lotCounter) revert HOUSE_InvalidLotId(id_);      
        
        // Get lot type
        Keycode auctionType = lotType[id_];

        // Load module, will revert if not installed
        return AuctionModule(_getModuleIfInstalled(auctionType));
    }

    // TODO, these functions need to be moved to the Router and integrated with the _handle functions

    // function purchase(uint256 id_, uint256 amount_, uint256 minAmountOut_) external override permissioned returns (uint256 payout) {
    //     AuctionModule module = _getModuleForId(id_);

    //     // Send purchase to module and return payout
    //     payout = module.purchase(id_, amount_, minAmountOut_);
    // }

    // function settle(uint256 id_, Auction.Bid[] memory bids_) external override returns (uint256[] memory amountsOut) {
    //     AuctionModule module = _getModuleForId(id_);

    //     // Send purchase to module and return amountsOut payout
    //     amountsOut = module.settle(id_, bids_);
    // }

    // ========== AUCTION MANAGEMENT ========== //

    function auction(RoutingParams calldata routing_, Auction.AuctionParams calldata params_) external override returns (uint256 id) {
        // Load auction type module, this checks that it is installed.
        // We load it here vs. later to avoid two checks.
        AuctionModule auctionModule = AuctionModule(_getModuleIfInstalled(routing_.auctionType));

        // Check that the auction type is allowing new auctions to be created
        if (typeSunset[auctionType_]) revert HOUSE_AuctionTypeSunset(routing_.auctionType);

        // Increment lot count and get ID
        id = lotCounter++;

        // Call module auction function to store implementation-specific data
        module.auction(id, params_);

        // Validate routing information

        // Confirm tokens are within the required decimal range
        uint8 payoutTokenDecimals = params_.payoutToken.decimals();
        uint8 quoteTokenDecimals = params_.quoteToken.decimals();

        if (payoutTokenDecimals < 6 || payoutTokenDecimals > 18)
            revert Auctioneer_InvalidParams();
        if (quoteTokenDecimals < 6 || quoteTokenDecimals > 18)
            revert Auctioneer_InvalidParams();

        // If payout is a derivative, validate derivative data on the derivative module
        if (routing_.derivativeType != toKeycode("")) {
            // Load derivative module, this checks that it is installed.
            DerivativeModule derivativeModule = DerivativeModule(_getModuleIfInstalled(routing_.derivativeType));

            // Call module validate function to validate implementation-specific data
            derivativeModule.validate(routing_.derivativeParams);
        }

        // If allowlist is being used, validate the allowlist data and register the auction on the allowlist
        if (address(routing_.allowlist) != address(0)) {
            // TODO
        }

        // Store routing information
        Routing storage routing = lotRouting[id];
        routing.auctionType = auctionType_;
        routing.owner = msg.sender;
        routing.payoutToken = routing_.payoutToken;
        routing.quoteToken = routing_.quoteToken;
        routing.hooks = routing_.hooks;


    }

    function close(uint256 id_) external override {
        AuctionModule module = _getModuleForId(id_);

        // Close the auction on the module
        // Module checks that msg.sender is auction owner
        module.close(id_, msg.sender);
    }

    // ========== AUCTION INFORMATION ========== //

    function getRouting(uint256 id_) external view override returns (Routing memory) {
        // Check that lot ID is valid
        if (id_ >= lotCounter) revert HOUSE_InvalidLotId(id_);

        // Get routing from lot routing
        return lotRouting[id_];
    }

    // TODO need to add the fee calculations back in at this level for all of these functions
    function payoutFor(uint256 id_, uint256 amount_) external view override returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get payout from module
        return module.payoutFor(id_, amount_);
    }

    function priceFor(uint256 id_, uint256 payout_) external view override returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get price from module
        return module.priceFor(id_, payout_);
    }

    function maxPayout(uint256 id_) external view override returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get max payout from module
        return module.maxPayout(id_);
    }

    function maxAmountAccepted(uint256 id_) external view override returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get max amount accepted from module
        return module.maxAmountAccepted(id_);
    }

    function isLive(uint256 id_) external view override returns (bool) {
        AuctionModule module = _getModuleForId(id_);

        // Get isLive from module
        return module.isLive(id_);
    }

    function ownerOf(uint256 id_) external view override returns (address) {
        // Check that lot ID is valid
        if (id_ >= lotCounter) revert HOUSE_InvalidLotId(id_);

        // Get owner from lot routing
        return lotRouting[id_].owner;
    }

    function remainingCapacity(id_) external view override returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get remaining capacity from module
        return module.remainingCapacity(id_);
    }
}