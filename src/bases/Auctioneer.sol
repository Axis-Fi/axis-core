/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

import "src/modules/Auction.sol";
import {DerivativeModule} from "src/modules/Derivative.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";

abstract contract Auctioneer is WithModules {
    // ========= ERRORS ========= //
    error InvalidParams();
    error InvalidLotId(uint256 id_);
    error InvalidModuleType(Veecode reference_);
    error NotAuctionOwner(address caller_);

    // ========= EVENTS ========= //
    event AuctionCreated(uint256 id, address baseToken, address quoteToken);

    // ========= DATA STRUCTURES ========== //

    /// @notice Auction routing information for a lot
    struct Routing {
        Veecode auctionReference; // auction module, represented by its Veecode
        address owner; // market owner. sends payout tokens, receives quote tokens
        ERC20 baseToken; // token provided by seller
        ERC20 quoteToken; // token to accept as payment
        IHooks hooks; // (optional) address to call for any hooks to be executed on a purchase. Must implement IHooks.
        IAllowlist allowlist; // (optional) contract that implements an allowlist for the market, based on IAllowlist
        Veecode derivativeReference; // (optional) derivative module, represented by its Veecode. If not set, no derivative will be created.
        bytes derivativeParams; // (optional) abi-encoded data to be used to create payout derivatives on a purchase
        bool wrapDerivative; // (optional) whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format.
    }

    struct RoutingParams {
        Keycode auctionType;
        ERC20 baseToken;
        ERC20 quoteToken;
        IHooks hooks;
        IAllowlist allowlist;
        bytes allowlistParams;
        bytes payoutData;
        Keycode derivativeType; // (optional) derivative type, represented by the Keycode for the derivative submodule. If not set, no derivative will be created.
        bytes derivativeParams; // (optional) data to be used to create payout derivatives on a purchase
    }

    // ========= STATE ========== //

    // 1% = 1_000 or 1e3. 100% = 100_000 or 1e5.
    uint48 internal constant ONE_HUNDRED_PERCENT = 1e5;

    /// @notice Counter for auction lots
    uint256 public lotCounter;

    /// @notice Mapping of lot IDs to their auction type (represented by the Keycode for the auction submodule)
    mapping(uint256 lotId => Routing) public lotRouting;

    /// @notice Mapping auction and derivative references to the condenser that is used to pass data between them
    mapping(Veecode auctionRef => mapping(Veecode derivativeRef => Veecode condenserRef)) public
        condensers;

    // ========== AUCTION MANAGEMENT ========== //

    function auction(
        RoutingParams calldata routing_,
        Auction.AuctionParams calldata params_
    ) external returns (uint256 id) {
        // Load auction type module, this checks that it is installed.
        // We load it here vs. later to avoid two checks.
        AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(routing_.auctionType));
        Veecode auctionRef = auctionModule.VEECODE();

        // Increment lot count and get ID
        id = lotCounter++;

        // Call module auction function to store implementation-specific data
        auctionModule.auction(id, params_);

        // Validate routing information

        // Confirm tokens are within the required decimal range
        uint8 baseTokenDecimals = routing_.baseToken.decimals();
        uint8 quoteTokenDecimals = routing_.quoteToken.decimals();

        if (baseTokenDecimals < 6 || baseTokenDecimals > 18) {
            revert InvalidParams();
        }
        if (quoteTokenDecimals < 6 || quoteTokenDecimals > 18) {
            revert InvalidParams();
        }

        // Store routing information
        Routing storage routing = lotRouting[id];
        routing.auctionReference = auctionRef;
        routing.owner = msg.sender;
        routing.baseToken = routing_.baseToken;
        routing.quoteToken = routing_.quoteToken;
        routing.hooks = routing_.hooks;

        // If payout is a derivative, validate derivative data on the derivative module
        if (fromKeycode(routing_.derivativeType) != bytes5("")) {
            // Load derivative module, this checks that it is installed.
            DerivativeModule derivative =
                DerivativeModule(_getLatestModuleIfActive(routing_.derivativeType));
            Veecode derivativeRef = derivative.VEECODE();

            // Call module validate function to validate implementation-specific data
            if (!derivative.validate(routing_.derivativeParams)) revert InvalidParams();

            // Store derivative information
            routing.derivativeReference = derivativeRef;
            routing.derivativeParams = routing_.derivativeParams;
        }

        // If allowlist is being used, validate the allowlist data and register the auction on the allowlist
        if (address(routing_.allowlist) != address(0)) {
            // TODO
        }

        emit AuctionCreated(id, address(routing.baseToken), address(routing.quoteToken));
    }

    function cancel(uint256 id_) external {
        // Check that caller is the auction owner
        if (msg.sender != lotRouting[id_].owner) revert NotAuctionOwner(msg.sender);

        AuctionModule module = _getModuleForId(id_);

        // Cancel the auction on the module
        module.cancel(id_);
    }

    // ========== AUCTION INFORMATION ========== //

    function getRouting(uint256 id_) external view returns (Routing memory) {
        // Check that lot ID is valid
        if (id_ >= lotCounter) revert InvalidLotId(id_);

        // Get routing from lot routing
        return lotRouting[id_];
    }

    // TODO need to add the fee calculations back in at this level for all of these functions
    function payoutFor(uint256 id_, uint256 amount_) external view returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get payout from module
        return module.payoutFor(id_, amount_);
    }

    function priceFor(uint256 id_, uint256 payout_) external view returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get price from module
        return module.priceFor(id_, payout_);
    }

    function maxPayout(uint256 id_) external view returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get max payout from module
        return module.maxPayout(id_);
    }

    function maxAmountAccepted(uint256 id_) external view returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get max amount accepted from module
        return module.maxAmountAccepted(id_);
    }

    function isLive(uint256 id_) external view returns (bool) {
        AuctionModule module = _getModuleForId(id_);

        // Get isLive from module
        return module.isLive(id_);
    }

    function ownerOf(uint256 id_) external view returns (address) {
        // Check that lot ID is valid
        if (id_ >= lotCounter) revert InvalidLotId(id_);

        // Get owner from lot routing
        return lotRouting[id_].owner;
    }

    function remainingCapacity(uint256 id_) external view returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get remaining capacity from module
        return module.remainingCapacity(id_);
    }

    // ========== INTERNAL HELPER FUNCTIONS ========== //

    function _getModuleForId(uint256 id_) internal view returns (AuctionModule) {
        // Confirm lot ID is valid
        if (id_ >= lotCounter) revert InvalidLotId(id_);

        // Load module, will revert if not installed
        return AuctionModule(_getModuleIfInstalled(lotRouting[id_].auctionReference));
    }

    // ========== GOVERNANCE FUNCTIONS ========== //

    // TODO set access control
    function setCondenser(
        Veecode auctionRef_,
        Veecode derivativeRef_,
        Veecode condenserRef_
    ) external {
        // Validate that the modules are installed and of the correct type
        Module auctionModule = Module(_getModuleIfInstalled(auctionRef_));
        Module derivativeModule = Module(_getModuleIfInstalled(derivativeRef_));
        Module condenserModule = Module(_getModuleIfInstalled(condenserRef_));

        if (auctionModule.TYPE() != Module.Type.Auction) revert InvalidModuleType(auctionRef_);
        if (derivativeModule.TYPE() != Module.Type.Derivative) {
            revert InvalidModuleType(derivativeRef_);
        }
        if (condenserModule.TYPE() != Module.Type.Condenser) {
            revert InvalidModuleType(condenserRef_);
        }

        condensers[auctionRef_][derivativeRef_] = condenserRef_;
    }
}
