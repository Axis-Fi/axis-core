/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

import "src/modules/Auction.sol";

import {fromKeycode, Module} from "src/modules/Modules.sol";

import {DerivativeModule} from "src/modules/Derivative.sol";
import {CondenserModule} from "src/modules/Condenser.sol";

interface IHooks {}

interface IAllowlist {}

abstract contract Auctioneer is WithModules {
    // ========= ERRORS ========= //

    error HOUSE_AuctionTypeSunset(Keycode auctionType);

    error HOUSE_NotAuctionOwner(address caller);

    error HOUSE_InvalidLotId(uint256 id);

    error Auctioneer_Params_InvalidTokenDecimals(address token_, uint8 decimals_);

    error Auctioneer_Params_InvalidToken(address token_);

    error Auctioneer_Params_InvalidDuration(uint48 duration_);

    error Auctioneer_Params_InvalidType(Module.Type expectedType_, Module.Type actualType_);

    error Auctioneer_Params_InvalidCondenser(
        Keycode auctionKeycode_, Keycode derivativeKeycode_, Keycode condenserKeycode_
    );

    error Auctioneer_InvalidParams();

    // ========= EVENTS ========= //

    event AuctionCreated(uint256 indexed id, address indexed baseToken, address indexed quoteToken);

    // ========= DATA STRUCTURES ========== //

    /// @notice Auction routing information for a lot
    struct Routing {
        Veecode auctionType; // auction type, represented by the Keycode for the auction submodule
        address owner; // market owner. sends payout tokens, receives quote tokens
        ERC20 baseToken; // token provided by seller
        ERC20 quoteToken; // token to accept as payment
        IHooks hooks; // (optional) address to call for any hooks to be executed on a purchase. Must implement IHooks.
        IAllowlist allowlist; // (optional) contract that implements an allowlist for the market, based on IAllowlist
        Veecode derivativeType; // (optional) derivative type, represented by the Keycode for the derivative submodule. If not set, no derivative will be created.
        bytes derivativeParams; // (optional) abi-encoded data to be used to create payout derivatives on a purchase
        bool wrapDerivative; // (optional) whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format.
        Veecode condenserType; // (optional) condenser type, represented by the Keycode for the condenser submodule. If not set, no condenser will be used. TODO should a condenser be stored on the auctionhouse for a particular auction/derivative combination and looked up?
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

    /// @notice     Maps auction and derivative types to the Condenser module that handles them
    /// @dev        Auction Keycode -> Derivative Keycode -> Condenser Keycode
    mapping(Keycode => mapping(Keycode => Keycode)) public condenserLookup;

    // ========== AUCTION MANAGEMENT ========== //

    /// @notice     Creates a new auction lot
    /// @dev        The function reverts if:
    ///             - The module for the auction type is not installed
    ///             - The auction type is sunset
    ///             - The base token or quote token decimals are not within the required range
    ///             - Validation for the auction parameters fails
    ///             - The module for the optional specified derivative type is not installed
    ///             - Validation for the optional specified derivative type fails
    ///             - Validation for the optional allowlist fails
    ///             - The module for the optional specified condenser type is not installed
    ///
    /// @param      routing_    Routing information for the auction lot
    /// @param      params_     Auction parameters for the auction lot
    /// @return     lotId       ID of the auction lot
    function auction(
        RoutingParams calldata routing_,
        Auction.AuctionParams calldata params_
    ) external returns (uint256 lotId) {
        // Load auction type module, this checks that it is installed.
        // We load it here vs. later to avoid two checks.
        Keycode auctionType = routing_.auctionType;
        AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(auctionType));

        // Check that the auction type is allowing new auctions to be created
        if (typeSunset[auctionType]) revert HOUSE_AuctionTypeSunset(auctionType);

        // Check that the module for the auction type is valid
        if (auctionModule.TYPE() != Module.Type.Auction) {
            revert Auctioneer_Params_InvalidType(Module.Type.Auction, auctionModule.TYPE());
        }

        // Increment lot count and get ID
        lotId = lotCounter++;

        // Auction Module
        {
            // Call module auction function to store implementation-specific data
            auctionModule.auction(lotId, params_);
        }

        // Routing
        {
            // Validate routing information
            if (address(routing_.baseToken) == address(0)) {
                revert Auctioneer_Params_InvalidToken(address(routing_.baseToken));
            }
            if (address(routing_.quoteToken) == address(0)) {
                revert Auctioneer_Params_InvalidToken(address(routing_.quoteToken));
            }

            // Confirm tokens are within the required decimal range
            uint8 baseTokenDecimals = routing_.baseToken.decimals();
            uint8 quoteTokenDecimals = routing_.quoteToken.decimals();

            if (baseTokenDecimals < 6 || baseTokenDecimals > 18) {
                revert Auctioneer_Params_InvalidTokenDecimals(
                    address(routing_.baseToken), baseTokenDecimals
                );
            }
            if (quoteTokenDecimals < 6 || quoteTokenDecimals > 18) {
                revert Auctioneer_Params_InvalidTokenDecimals(
                    address(routing_.quoteToken), quoteTokenDecimals
                );
            }
        }

        // Derivative
        Veecode derivativeType;
        bytes memory derivativeParams;
        if (fromKeycode(routing_.derivativeType) != bytes5(0)) {
            // Load derivative module, this checks that it is installed.
            DerivativeModule derivativeModule =
                DerivativeModule(_getLatestModuleIfActive(routing_.derivativeType));

            // Check that the module for the derivative type is valid
            if (derivativeModule.TYPE() != Module.Type.Derivative) {
                revert Auctioneer_Params_InvalidType(
                    Module.Type.Derivative, derivativeModule.TYPE()
                );
            }

            // Call module validate function to validate implementation-specific data
            derivativeModule.validate(routing_.derivativeParams);

            derivativeType = derivativeModule.VEECODE();
            derivativeParams = routing_.derivativeParams;
        }

        // Condenser
        // TODO: decide if routing_.condenserType is an override for the existing lookup, otherwise do the lookup only if the condenserType is not specified
        Veecode condenserType;
        if (fromKeycode(routing_.condenserType) != bytes5(0)) {
            // Load condenser module, this checks that it is installed.
            CondenserModule condenserModule =
                CondenserModule(_getLatestModuleIfActive(routing_.condenserType));

            // Check that the module for the condenser type is valid
            if (condenserModule.TYPE() != Module.Type.Condenser) {
                revert Auctioneer_Params_InvalidType(Module.Type.Condenser, condenserModule.TYPE());
            }

            // Check that the condenser type is valid for the auction and derivative types
            if (
                fromKeycode(condenserLookup[routing_.auctionType][routing_.derivativeType])
                    != fromKeycode(routing_.condenserType)
            ) {
                revert Auctioneer_Params_InvalidCondenser(
                    routing_.auctionType, routing_.derivativeType, routing_.condenserType
                );
            }

            condenserType = condenserModule.VEECODE();
        }

        // If allowlist is being used, validate the allowlist data and register the auction on the allowlist
        if (address(routing_.allowlist) != address(0)) {
            // TODO
        }

        // Store routing information
        Routing storage routing = lotRouting[lotId];
        routing.auctionType = auctionModule.VEECODE();
        routing.owner = msg.sender;
        routing.baseToken = routing_.baseToken;
        routing.quoteToken = routing_.quoteToken;
        routing.hooks = routing_.hooks;
        routing.derivativeType = derivativeType;
        routing.derivativeParams = derivativeParams;
        routing.condenserType = condenserType;

        emit AuctionCreated(lotId, address(routing.baseToken), address(routing.quoteToken));
    }

    /// @notice     Cancels an auction lot
    /// @dev        The function reverts if:
    ///             - The caller is not the auction owner
    ///             - The lot ID is invalid
    ///             - The respective auction module reverts
    ///
    /// @param      lotId_      ID of the auction lot
    function cancel(uint256 lotId_) external {
        address lotOwner = lotRouting[lotId_].owner;
        // Check that it is a valid lot id
        if (lotOwner == address(0)) revert HOUSE_InvalidLotId(lotId_);

        // Check that caller is the auction owner
        if (msg.sender != lotOwner) revert HOUSE_NotAuctionOwner(msg.sender);

        AuctionModule module = _getModuleForId(lotId_);

        // Cancel the auction on the module
        module.cancel(lotId_);
    }

    // ========== AUCTION INFORMATION ========== //

    function getRouting(uint256 id_) external view returns (Routing memory) {
        // Check that lot ID is valid
        if (id_ >= lotCounter) revert HOUSE_InvalidLotId(id_);

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
        if (id_ >= lotCounter) revert HOUSE_InvalidLotId(id_);

        // Get owner from lot routing
        return lotRouting[id_].owner;
    }

    function remainingCapacity(uint256 id_) external view returns (uint256) {
        AuctionModule module = _getModuleForId(id_);

        // Get remaining capacity from module
        return module.remainingCapacity(id_);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice     Sets the value of the Condenser for a given auction and derivative combination
    /// @dev        To remove a condenser, set the value of `condenserType_` to a blank Keycode
    ///
    /// @dev        This function will revert if:
    /// @dev        - The caller is not the owner
    /// @dev        - `auctionKeycode_` or `derivativeKeycode_` are empty
    /// @dev        - `auctionKeycode_` does not belong to an auction module
    /// @dev        - `derivativeKeycode_` does not belong to a derivative module
    /// @dev        - `condenserType_` does not belong to a condenser module
    ///
    /// @param      auctionKeycode_    The auction type
    /// @param      derivativeKeycode_ The derivative type
    /// @param      condenserKeycode_  The condenser type
    function setCondenserLookup(
        Keycode auctionKeycode_,
        Keycode derivativeKeycode_,
        Keycode condenserKeycode_
    ) external onlyOwner {
        // Check that auction and derivative keycodes are not empty
        if (fromKeycode(auctionKeycode_) == bytes5(0)) {
            revert Auctioneer_Params_InvalidCondenser(
                auctionKeycode_, derivativeKeycode_, condenserKeycode_
            );
        }

        if (fromKeycode(derivativeKeycode_) == bytes5(0)) {
            revert Auctioneer_Params_InvalidCondenser(
                auctionKeycode_, derivativeKeycode_, condenserKeycode_
            );
        }

        // Check that the auction type is valid
        {
            AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(auctionKeycode_));

            if (auctionModule.TYPE() != Module.Type.Auction) {
                revert Auctioneer_Params_InvalidCondenser(
                    auctionKeycode_, derivativeKeycode_, condenserKeycode_
                );
            }
        }

        // Check that the derivative type is valid
        {
            DerivativeModule derivativeModule =
                DerivativeModule(_getLatestModuleIfActive(derivativeKeycode_));

            if (derivativeModule.TYPE() != Module.Type.Derivative) {
                revert Auctioneer_Params_InvalidCondenser(
                    auctionKeycode_, derivativeKeycode_, condenserKeycode_
                );
            }
        }

        // Check that the condenser type is valid
        if (fromKeycode(condenserKeycode_) != bytes5(0)) {
            CondenserModule condenserModule =
                CondenserModule(_getLatestModuleIfActive(condenserKeycode_));

            if (condenserModule.TYPE() != Module.Type.Condenser) {
                revert Auctioneer_Params_InvalidCondenser(
                    auctionKeycode_, derivativeKeycode_, condenserKeycode_
                );
            }
        }

        condenserLookup[auctionKeycode_][derivativeKeycode_] = condenserKeycode_;
    }

    // ========== INTERNAL HELPER FUNCTIONS ========== //

    function _getModuleForId(uint256 id_) internal view returns (AuctionModule) {
        // Confirm lot ID is valid
        if (id_ >= lotCounter) revert HOUSE_InvalidLotId(id_);

        // Load module, will revert if not installed
        return AuctionModule(_getModuleIfInstalled(lotRouting[id_].auctionType));
    }
}
