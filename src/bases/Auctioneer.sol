/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

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
    using SafeTransferLib for ERC20;

    // ========= ERRORS ========= //

    error InvalidParams();
    error InvalidLotId(uint96 id_);
    error InvalidModuleType(Veecode reference_);
    error NotAuctionOwner(address caller_);
    error NotCurator(address caller_);
    error InvalidState();
    error InvalidHook();
    error UnsupportedToken(address token_);

    // ========= EVENTS ========= //

    event AuctionCreated(
        uint96 id, Veecode indexed auctionRef, address baseToken, address quoteToken
    );
    event AuctionCancelled(uint96 id, Veecode indexed auctionRef);
    event Curated(uint96 indexed id, address indexed curator);

    // ========= DATA STRUCTURES ========== //

    /// @notice     Auction routing information for a lot
    /// @param      auctionReference    Auction module, represented by its Veecode
    /// @param      owner               Lot owner
    /// @param      baseToken           Token provided by seller
    /// @param      quoteToken          Token to accept as payment
    /// @param      curator             (optional) Address of the proposed curator
    /// @param      curated             (optional) Whether the curator has approved the auction
    /// @param      hooks               (optional) Address to call for any hooks to be executed
    /// @param      allowlist           (optional) Contract that implements an allowlist for the auction lot
    /// @param      derivativeReference (optional) Derivative module, represented by its Veecode
    /// @param      derivativeParams    (optional) abi-encoded data to be used to create payout derivatives on a purchase
    /// @param      wrapDerivative      (optional) Whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format
    /// @param      prefunded           Set by the auction module if the auction is prefunded
    struct Routing {
        Veecode auctionReference;
        address owner;
        ERC20 baseToken;
        ERC20 quoteToken;
        address curator;
        bool curated;
        IHooks hooks;
        IAllowlist allowlist;
        Veecode derivativeReference;
        bytes derivativeParams;
        bool wrapDerivative;
        bool prefunded;
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

    /// @notice     Constant representing 100%
    /// @dev        1% = 1_000 or 1e3. 100% = 100_000 or 1e5
    uint48 internal constant _ONE_HUNDRED_PERCENT = 1e5;

    /// @notice     Counter for auction lots
    uint96 public lotCounter;

    /// @notice Mapping of lot IDs to their auction type (represented by the Keycode for the auction submodule)
    mapping(uint96 lotId => Routing) public lotRouting;

    /// @notice Mapping auction and derivative references to the condenser that is used to pass data between them
    mapping(Veecode auctionRef => mapping(Veecode derivativeRef => Veecode condenserRef)) public
        condensers;

    // ========= MODIFIERS ========= //

    /// @notice     Checks that the lot ID is valid
    /// @dev        Reverts if the lot ID is invalid
    ///
    /// @param      lotId_  ID of the auction lot
    modifier isLotValid(uint96 lotId_) {
        if (lotId_ >= lotCounter) revert InvalidLotId(lotId_);

        if (lotRouting[lotId_].owner == address(0)) revert InvalidLotId(lotId_);
        _;
    }

    /// @notice     Checks that the caller is the auction owner
    /// @dev        Reverts if the caller is not the auction owner
    ///
    /// @param      lotId_  ID of the auction lot
    modifier isLotOwner(uint96 lotId_) {
        if (msg.sender != lotRouting[lotId_].owner) revert NotAuctionOwner(msg.sender);
        _;
    }

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
    ///
    /// @param      routing_    Routing information for the auction lot
    /// @param      params_     Auction parameters for the auction lot
    /// @return     lotId       ID of the auction lot
    function auction(
        RoutingParams calldata routing_,
        Auction.AuctionParams calldata params_
    ) external returns (uint96 lotId) {
        // Load auction type module, this checks that it is installed.
        // We load it here vs. later to avoid two checks.
        AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(routing_.auctionType));
        Veecode auctionRef = auctionModule.VEECODE();

        // Check that the module for the auction type is valid
        if (auctionModule.TYPE() != Module.Type.Auction) {
            revert InvalidModuleType(auctionRef);
        }

        // Validate routing parameters
        uint8 quoteTokenDecimals;
        uint8 baseTokenDecimals;
        {
            // Validate routing information
            if (address(routing_.baseToken) == address(0)) {
                revert InvalidParams();
            }
            if (address(routing_.quoteToken) == address(0)) {
                revert InvalidParams();
            }

            // Confirm tokens are within the required decimal range
            baseTokenDecimals = routing_.baseToken.decimals();
            quoteTokenDecimals = routing_.quoteToken.decimals();

            if (baseTokenDecimals < 6 || baseTokenDecimals > 18) {
                revert InvalidParams();
            }
            if (quoteTokenDecimals < 6 || quoteTokenDecimals > 18) {
                revert InvalidParams();
            }
        }

        // Increment lot count and get ID
        lotId = lotCounter++;

        // Auction Module
        bool requiresPrefunding;
        uint256 lotCapacity;
        {
            // Call module auction function to store implementation-specific data
            (requiresPrefunding, lotCapacity) =
                auctionModule.auction(lotId, params_, quoteTokenDecimals, baseTokenDecimals);
        }

        // Store routing information
        Routing storage routing = lotRouting[lotId];
        routing.auctionReference = auctionRef;
        routing.owner = msg.sender;
        routing.baseToken = routing_.baseToken;
        routing.quoteToken = routing_.quoteToken;

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
            routing.prefunded = true;

            // Get the balance of the base token before the transfer
            uint256 balanceBefore = routing_.baseToken.balanceOf(address(this));

            // Call hook on hooks contract if provided
            if (address(routing_.hooks) != address(0)) {
                // The pre-auction create hook should transfer the base token to this contract
                routing_.hooks.preAuctionCreate(lotId);

                // Check that the hook transferred the expected amount of base tokens
                if (routing_.baseToken.balanceOf(address(this)) < balanceBefore + lotCapacity) {
                    revert InvalidHook();
                }
            }
            // Otherwise fallback to a standard ERC20 transfer
            else {
                // Transfer the base token from the auction owner
                // `safeTransferFrom()` will revert upon failure or the lack of allowance or balance
                routing_.baseToken.safeTransferFrom(msg.sender, address(this), lotCapacity);

                // Check that it is not a fee-on-transfer token
                if (routing_.baseToken.balanceOf(address(this)) < balanceBefore + lotCapacity) {
                    revert UnsupportedToken(address(routing_.baseToken));
                }
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
    ///
    /// @param      lotId_      ID of the auction lot
    function cancel(uint96 lotId_) external isLotValid(lotId_) isLotOwner(lotId_) {
        AuctionModule module = _getModuleForId(lotId_);

        // Get remaining capacity from module
        uint256 lotRemainingCapacity = module.remainingCapacity(lotId_);

        // Cancel the auction on the module
        module.cancelAuction(lotId_);

        // If the auction is prefunded and supported, transfer the remaining capacity to the owner
        if (lotRouting[lotId_].prefunded == true && lotRemainingCapacity > 0) {
            // Transfer payout tokens to the owner
            Routing memory routing = lotRouting[lotId_];
            routing.baseToken.safeTransfer(routing.owner, lotRemainingCapacity);
        }

        emit AuctionCancelled(lotId_, lotRouting[lotId_].auctionReference);
    }

    // ========== AUCTION INFORMATION ========== //

    /// @notice     Gets the routing information for a given lot ID
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///
    /// @param      id_     ID of the auction lot
    /// @return     routing Routing information for the auction lot
    function getRouting(uint96 id_) external view isLotValid(id_) returns (Routing memory) {
        // Get routing from lot routing
        return lotRouting[id_];
    }

    
    function payoutFor(uint96 id_, uint256 amount_) external view virtual returns (uint256);

    function priceFor(uint96 id_, uint256 payout_) external view virtual returns (uint256);

    function maxPayout(uint96 id_) external view virtual returns (uint256);

    function maxAmountAccepted(uint96 id_) external view virtual returns (uint256);

    /// @notice    Returns whether the auction is currently accepting bids or purchases
    /// @dev       Auctions that have been created, but not yet started will return false
    function isLive(uint96 id_) external view returns (bool) {
        AuctionModule module = _getModuleForId(id_);

        // Get isLive from module
        return module.isLive(id_);
    }

    function hasEnded(uint96 id_) external view returns (bool) {
        AuctionModule module = _getModuleForId(id_);

        // Get hasEnded from module
        return module.hasEnded(id_);
    }

    function ownerOf(uint96 id_) external view returns (address) {
        // Check that lot ID is valid
        if (id_ >= lotCounter) revert InvalidLotId(id_);

        // Get owner from lot routing
        return lotRouting[id_].owner;
    }

    function remainingCapacity(uint96 id_) external view returns (uint256) {
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
    function _getModuleForId(uint96 lotId_) internal view returns (AuctionModule) {
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
