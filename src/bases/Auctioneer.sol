/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

import {
    fromKeycode,
    Keycode,
    fromVeecode,
    unwrapVeecode,
    Veecode,
    Module,
    WithModules
} from "src/modules/Modules.sol";

import {Auction, AuctionModule} from "src/modules/Auction.sol";

import {DerivativeModule} from "src/modules/Derivative.sol";
import {CondenserModule} from "src/modules/Condenser.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";

/// @title  Auctioneer
/// @notice The Auctioneer handles the following:
///         - Creating new auction lots
///         - Cancelling auction lots
///         - Storing information about how to handle inputs and outputs for auctions ("routing")
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

    /// @notice     Auction routing information provided as input parameters
    /// @dev        After validation, this information is stored in the Routing struct
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

    /// @notice     Constant representing 100%
    /// @dev        1% = 1_000 or 1e3. 100% = 100_000 or 1e5
    uint48 internal constant ONE_HUNDRED_PERCENT = 1e5;

    /// @notice     Counter for auction lots
    uint256 public lotCounter;

    /// @notice Mapping of lot IDs to their auction type (represented by the Keycode for the auction submodule)
    mapping(uint256 lotId => Routing) public lotRouting;

    /// @notice Mapping auction and derivative references to the condenser that is used to pass data between them
    mapping(Veecode auctionRef => mapping(Veecode derivativeRef => Veecode condenserRef)) public
        condensers;

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
        AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(routing_.auctionType));
        Veecode auctionRef = auctionModule.VEECODE();

        // Check that the module for the auction type is valid
        if (auctionModule.TYPE() != Module.Type.Auction) {
            revert InvalidModuleType(auctionRef);
        }

        // Increment lot count and get ID
        lotId = lotCounter++;

        // Auction Module
        {
            // Call module auction function to store implementation-specific data
            auctionModule.auction(lotId, params_);
        }

        // Validate routing parameters
        {
            // Validate routing information
            if (address(routing_.baseToken) == address(0)) {
                revert InvalidParams();
            }
            if (address(routing_.quoteToken) == address(0)) {
                revert InvalidParams();
            }

            // Confirm tokens are within the required decimal range
            uint8 baseTokenDecimals = routing_.baseToken.decimals();
            uint8 quoteTokenDecimals = routing_.quoteToken.decimals();

            if (baseTokenDecimals < 6 || baseTokenDecimals > 18) {
                revert InvalidParams();
            }
            if (quoteTokenDecimals < 6 || quoteTokenDecimals > 18) {
                revert InvalidParams();
            }
        }

        // Store routing information
        Routing storage routing = lotRouting[lotId];
        routing.auctionReference = auctionRef;
        routing.owner = msg.sender;
        routing.baseToken = routing_.baseToken;
        routing.quoteToken = routing_.quoteToken;
        routing.hooks = routing_.hooks;

        // Derivative
        if (fromKeycode(routing_.derivativeType) != bytes5("")) {
            // Load derivative module, this checks that it is installed.
            DerivativeModule derivativeModule =
                DerivativeModule(_getLatestModuleIfActive(routing_.derivativeType));
            Veecode derivativeRef = derivativeModule.VEECODE();

            // Check that the module for the derivative type is valid
            if (derivativeModule.TYPE() != Module.Type.Derivative) {
                revert InvalidModuleType(derivativeRef);
            }

            // Call module validate function to validate implementation-specific data
            if (!derivativeModule.validate(routing_.derivativeParams)) revert InvalidParams();

            // Store derivative information
            routing.derivativeReference = derivativeRef;
            routing.derivativeParams = routing_.derivativeParams;
        }

        // Condenser
        {
            // Get condenser reference
            Veecode condenserRef = condensers[auctionRef][routing.derivativeReference];

            // Check that the module for the condenser type is valid
            if (fromVeecode(condenserRef) != bytes7(0)) {
                CondenserModule condenserModule =
                    CondenserModule(_getModuleIfInstalled(condenserRef));

                if (condenserModule.TYPE() != Module.Type.Condenser) {
                    revert InvalidModuleType(condenserRef);
                }

                // Check module status
                (Keycode moduleKeycode,) = unwrapVeecode(condenserRef);
                ModStatus memory status = getModuleStatus[moduleKeycode];
                if (status.sunset == true) {
                    revert ModuleIsSunset(moduleKeycode);
                }
            }
        }

        // If allowlist is being used, validate the allowlist data and register the auction on the allowlist
        if (address(routing_.allowlist) != address(0)) {
            // TODO validation
            // TODO registration with allowlist

            // Store allowlist information
            routing.allowlist = routing_.allowlist;
        }

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

        // Check that lot ID is valid
        if (lotOwner == address(0)) revert InvalidLotId(lotId_);

        // Check that caller is the auction owner
        if (msg.sender != lotOwner) revert NotAuctionOwner(msg.sender);

        AuctionModule module = _getModuleForId(lotId_);

        // Cancel the auction on the module
        module.cancel(lotId_);
    }

    // ========== AUCTION INFORMATION ========== //

    /// @notice     Gets the routing information for a given lot ID
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///
    /// @param      id_     ID of the auction lot
    /// @return     routing Routing information for the auction lot
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

    /// @notice     Gets the module for a given lot ID
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///             - The module for the auction type is not installed
    ///
    /// @param      lotId_      ID of the auction lot
    function _getModuleForId(uint256 lotId_) internal view returns (AuctionModule) {
        // Confirm lot ID is valid
        if (lotId_ >= lotCounter) revert InvalidLotId(lotId_);

        // Load module, will revert if not installed
        return AuctionModule(_getModuleIfInstalled(lotRouting[lotId_].auctionReference));
    }

    // ========== GOVERNANCE FUNCTIONS ========== //

    /// @notice     Sets the value of the Condenser for a given auction and derivative combination
    /// @dev        To remove a condenser, set the value of `condenserRef_` to a blank Veecode
    ///
    ///             This function will revert if:
    ///             - The caller is not the owner
    ///             - `auctionRef_` or `derivativeRef_` are empty
    ///             - `auctionRef_` does not belong to an auction module
    ///             - `derivativeRef_` does not belong to a derivative module
    ///             - `condenserRef_` does not belong to a condenser module
    ///
    /// @param      auctionRef_    The auction type
    /// @param      derivativeRef_ The derivative type
    /// @param      condenserRef_  The condenser type
    function setCondenser(
        Veecode auctionRef_,
        Veecode derivativeRef_,
        Veecode condenserRef_
    ) external onlyOwner {
        // Check that auction and derivative keycodes are not empty
        if (fromVeecode(auctionRef_) == bytes7(0)) {
            revert InvalidParams();
        }

        if (fromVeecode(derivativeRef_) == bytes7(0)) {
            revert InvalidParams();
        }

        // Check that the auction type is valid
        {
            AuctionModule auctionModule = AuctionModule(_getModuleIfInstalled(auctionRef_));

            if (auctionModule.TYPE() != Module.Type.Auction) {
                revert InvalidModuleType(auctionRef_);
            }
        }

        // Check that the derivative type is valid
        {
            DerivativeModule derivativeModule =
                DerivativeModule(_getModuleIfInstalled(derivativeRef_));

            if (derivativeModule.TYPE() != Module.Type.Derivative) {
                revert InvalidModuleType(derivativeRef_);
            }
        }

        // Check that the condenser type is valid
        if (fromVeecode(condenserRef_) != bytes7(0)) {
            CondenserModule condenserModule = CondenserModule(_getModuleIfInstalled(condenserRef_));

            if (condenserModule.TYPE() != Module.Type.Condenser) {
                revert InvalidModuleType(condenserRef_);
            }
        }

        condensers[auctionRef_][derivativeRef_] = condenserRef_;
    }
}
