/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {
    fromKeycode,
    Keycode,
    fromVeecode,
    keycodeFromVeecode,
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
abstract contract Auctioneer is WithModules, ReentrancyGuard {
    // ========= ERRORS ========= //

    error InvalidParams();
    error InvalidLotId(uint96 id_);
    error InvalidState();
    error InvalidHook();

    /// @notice     Used when the caller is not permitted to perform that action
    error NotPermitted(address caller_);

    // ========= EVENTS ========= //

    event AuctionCreated(
        uint96 indexed lotId, Veecode indexed auctionRef, address baseToken, address quoteToken
    );
    event AuctionCancelled(uint96 indexed lotId, Veecode indexed auctionRef);
    event Curated(uint96 indexed lotId, address indexed curator);

    // ========= DATA STRUCTURES ========== //

    /// @notice     Auction routing information for a lot
    /// @param      auctionReference    Auction module, represented by its Veecode
    /// @param      owner               Lot owner
    /// @param      baseToken           Token provided by seller
    /// @param      quoteToken          Token to accept as payment
    /// @param      hooks               (optional) Address to call for any hooks to be executed
    /// @param      allowlist           (optional) Contract that implements an allowlist for the auction lot
    /// @param      derivativeReference (optional) Derivative module, represented by its Veecode
    /// @param      derivativeParams    (optional) abi-encoded data to be used to create payout derivatives on a purchase
    /// @param      wrapDerivative      (optional) Whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format
    /// @param      prefunding          The amount of base tokens in prefunding remaining
    struct Routing {
        Veecode auctionReference;
        address owner;
        ERC20 baseToken;
        ERC20 quoteToken;
        IHooks hooks;
        IAllowlist allowlist;
        Veecode derivativeReference;
        bytes derivativeParams;
        bool wrapDerivative;
        uint256 prefunding;
    }

    /// @notice     Curation information for a lot
    /// @dev        This is split into a separate struct, otherwise the Routing struct would be too large
    ///             and would throw a "stack too deep" error.
    ///
    /// @param      curator     Address of the proposed curator
    /// @param      curated     Whether the curator has approved the auction
    struct Curation {
        address curator;
        bool curated;
    }

    /// @notice     Auction routing information provided as input parameters
    /// @dev        After validation, this information is stored in the Routing struct
    struct RoutingParams {
        Keycode auctionType;
        ERC20 baseToken;
        ERC20 quoteToken;
        address curator;
        IHooks hooks;
        IAllowlist allowlist;
        bytes allowlistParams;
        bytes payoutData;
        Keycode derivativeType; // (optional) derivative type, represented by the Keycode for the derivative submodule. If not set, no derivative will be created.
        bytes derivativeParams; // (optional) data to be used to create payout derivatives on a purchase
    }

    // ========= STATE ========== //

    /// @notice     Counter for auction lots
    uint96 public lotCounter;

    /// @notice     Mapping of lot IDs to their auction type (represented by the Keycode for the auction submodule)
    mapping(uint96 lotId => Routing) public lotRouting;

    /// @notice     Mapping of lot IDs to their curation information
    mapping(uint96 lotId => Curation) public lotCuration;

    /// @notice     Mapping auction and derivative references to the condenser that is used to pass data between them
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
    ///             - Registration for the optional allowlist fails
    ///             - The optional specified hooks contract is not a contract
    ///             - The condenser module is not installed or is sunset
    ///             - re-entrancy is detected
    ///
    /// @param      routing_    Routing information for the auction lot
    /// @param      params_     Auction parameters for the auction lot
    /// @return     lotId       ID of the auction lot
    function auction(
        RoutingParams calldata routing_,
        Auction.AuctionParams calldata params_
    ) external nonReentrant returns (uint96 lotId) {
        // Load auction type module, this checks that it is installed.
        // We load it here vs. later to avoid two checks.
        AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(routing_.auctionType));
        Veecode auctionRef = auctionModule.VEECODE();

        // Check that the module for the auction type is valid
        if (auctionModule.TYPE() != Module.Type.Auction) revert InvalidParams();

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

        // Call module auction function to store implementation-specific data
        (bool requiresPrefunding, uint256 lotCapacity) =
            auctionModule.auction(lotId, params_, quoteTokenDecimals, baseTokenDecimals);

        // Store routing information
        Routing storage routing = lotRouting[lotId];
        routing.auctionReference = auctionRef;
        routing.owner = msg.sender;
        routing.baseToken = routing_.baseToken;
        routing.quoteToken = routing_.quoteToken;

        // Store curation information
        {
            Curation storage curation = lotCuration[lotId];
            curation.curator = routing_.curator;
            curation.curated = false;
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
            routing.derivativeParams = routing_.derivativeParams;
        }

        // Condenser
        {
            // Get condenser reference
            Veecode condenserRef = condensers[auctionRef][routing.derivativeReference];

            // Check that the module for the condenser type is valid
            if (fromVeecode(condenserRef) != bytes7(0)) {
                if (
                    CondenserModule(_getModuleIfInstalled(condenserRef)).TYPE()
                        != Module.Type.Condenser
                ) revert InvalidParams();

                // Check module status
                Keycode moduleKeycode = keycodeFromVeecode(condenserRef);
                if (getModuleStatus[moduleKeycode].sunset == true) {
                    revert ModuleIsSunset(moduleKeycode);
                }
            }
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

        // If hooks are being used, validate the hooks data
        if (address(routing_.hooks) != address(0)) {
            // Check that it is a contract
            // It is assumed that the user will do validation of the hooks
            if (address(routing_.hooks).code.length == 0) revert InvalidParams();

            // Store hooks information
            routing.hooks = routing_.hooks;
        }

        // Perform pre-funding, if needed
        // It does not make sense to pre-fund the auction if the capacity is in quote tokens
        if (requiresPrefunding == true) {
            // Capacity must be in base token for auctions that require pre-funding
            if (params_.capacityInQuote) revert InvalidParams();

            // Store pre-funding information
            routing.prefunding = lotCapacity;

            // Call hook on hooks contract if provided
            if (address(routing_.hooks) != address(0)) {
                uint256 balanceBefore = routing_.baseToken.balanceOf(address(this));

                // The pre-auction create hook should transfer the base token to this contract
                routing_.hooks.preAuctionCreate(lotId);

                // Check that the hook transferred the expected amount of base tokens
                if (routing_.baseToken.balanceOf(address(this)) < balanceBefore + lotCapacity) {
                    revert InvalidHook();
                }
            }
            // Otherwise fallback to a standard ERC20 transfer
            else {
                Transfer.transferFrom(
                    routing_.baseToken, msg.sender, address(this), lotCapacity, true
                );
            }
        }

        emit AuctionCreated(
            lotId, auctionRef, address(routing_.baseToken), address(routing_.quoteToken)
        );
    }

    /// @notice     Cancels an auction lot
    /// @dev        This function performs the following:
    ///             - Checks that the lot ID is valid
    ///             - Checks that caller is the auction owner
    ///             - Calls the auction module to validate state, update records and determine the amount to be refunded
    ///             - If prefunded, sends the refund of payout tokens to the owner
    ///
    ///             The function reverts if:
    ///             - The lot ID is invalid
    ///             - The caller is not the auction owner
    ///             - The respective auction module reverts
    ///             - The transfer of payout tokens fails
    ///             - re-entrancy is detected
    ///
    /// @param      lotId_      ID of the auction lot
    function cancel(uint96 lotId_) external nonReentrant {
        // Validation
        _isLotValid(lotId_);

        Routing storage routing = lotRouting[lotId_];

        // Check ownership
        if (msg.sender != routing.owner) revert NotPermitted(msg.sender);

        // Cancel the auction on the module
        getModuleForId(lotId_).cancelAuction(lotId_);

        // If the auction is prefunded and supported, transfer the remaining capacity to the owner
        if (routing.prefunding > 0) {
            uint256 prefunding = routing.prefunding;

            // Set to 0 before transfer to avoid re-entrancy
            lotRouting[lotId_].prefunding = 0;

            // Transfer payout tokens to the owner
            Transfer.transfer(routing.baseToken, routing.owner, prefunding, false);
        }

        emit AuctionCancelled(lotId_, routing.auctionReference);
    }

    // ========== INTERNAL HELPER FUNCTIONS ========== //

    /// @notice     Gets the module for a given lot ID
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///             - The module for the auction type is not installed
    ///
    /// @param      lotId_      ID of the auction lot
    function getModuleForId(uint96 lotId_) public view returns (AuctionModule) {
        _isLotValid(lotId_);

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
        // Check that the auction type, derivative type, and condenser types are valid
        if (
            (AuctionModule(_getModuleIfInstalled(auctionRef_)).TYPE() != Module.Type.Auction)
                || (
                    DerivativeModule(_getModuleIfInstalled(derivativeRef_)).TYPE()
                        != Module.Type.Derivative
                )
                || (
                    fromVeecode(condenserRef_) != bytes7(0)
                        && CondenserModule(_getModuleIfInstalled(condenserRef_)).TYPE()
                            != Module.Type.Condenser
                )
        ) revert InvalidParams();

        // Set the condenser reference
        condensers[auctionRef_][derivativeRef_] = condenserRef_;
    }

    // ========= VALIDATION FUNCTIONS ========= //

    /// @notice     Checks that the lot ID is valid
    /// @dev        Reverts if the lot ID is invalid
    ///
    /// @param      lotId_  ID of the auction lot
    function _isLotValid(uint96 lotId_) internal view {
        if (lotId_ >= lotCounter) revert InvalidLotId(lotId_);

        if (lotRouting[lotId_].owner == address(0)) revert InvalidLotId(lotId_);
    }
}
