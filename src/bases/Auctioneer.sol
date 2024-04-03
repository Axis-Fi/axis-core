/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {ReentrancyGuard} from "lib/solmate/src/utils/ReentrancyGuard.sol";

import {fromKeycode, Keycode, Veecode, Module, WithModules} from "src/modules/Modules.sol";

import {Auction, AuctionModule} from "src/modules/Auction.sol";

import {DerivativeModule} from "src/modules/Derivative.sol";

import {ICallback} from "src/interfaces/ICallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @title  Auctioneer
/// @notice The Auctioneer handles the following:
///         - Creating new auction lots
///         - Cancelling auction lots
///         - Storing information about how to handle inputs and outputs for auctions ("routing")
abstract contract Auctioneer is WithModules, ReentrancyGuard {
    using Callbacks for ICallback;

    // ========= ERRORS ========= //

    error InvalidParams();
    error InvalidLotId(uint96 id_);
    error InvalidState();
    error InvalidCallback();

    /// @notice     Used when the caller is not permitted to perform that action
    error NotPermitted(address caller_);

    // ========= EVENTS ========= //

    /// @notice         Emitted when a new auction lot is created
    ///
    /// @param          lotId       ID of the auction lot
    /// @param          auctionRef  Auction module, represented by its Veecode
    /// @param          infoHash    IPFS hash of the auction information
    event AuctionCreated(uint96 indexed lotId, Veecode indexed auctionRef, string infoHash);

    /// @notice         Emitted when an auction lot is cancelled
    ///
    /// @param          lotId       ID of the auction lot
    /// @param          auctionRef  Auction module, represented by its Veecode
    event AuctionCancelled(uint96 indexed lotId, Veecode indexed auctionRef);

    /// @notice         Emitted when a curator accepts curation of an auction lot
    ///
    /// @param          lotId       ID of the auction lot
    /// @param          curator     Address of the curator
    event Curated(uint96 indexed lotId, address indexed curator);

    // ========= DATA STRUCTURES ========== //

    /// @notice     Auction routing information for a lot
    ///
    /// @param      auctionReference    Auction module, represented by its Veecode
    /// @param      seller              Lot seller
    /// @param      baseToken           Token provided by seller
    /// @param      quoteToken          Token to accept as payment
    /// @param      callbacks           (optional) Callbacks implementation for extended functionality
    /// @param      derivativeReference (optional) Derivative module, represented by its Veecode
    /// @param      derivativeParams    (optional) abi-encoded data to be used to create payout derivatives on a purchase
    /// @param      wrapDerivative      (optional) Whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format
    /// @param      funding             The amount of base tokens in funding remaining
    struct Routing {
        address seller; // 20 bytes
        uint96 funding; // 12 bytes
        ERC20 baseToken; // 20 bytes
        Veecode auctionReference; // 7 bytes
        ERC20 quoteToken; // 20 bytes
        ICallback callbacks; // 20 bytes
        Veecode derivativeReference; // 7 bytes
        bool wrapDerivative; // 1 byte
        bytes derivativeParams;
    }

    /// @notice     Fee information for a lot
    /// @dev        This is split into a separate struct, otherwise the Routing struct would be too large
    ///             and would throw a "stack too deep" error.
    ///
    ///             The curator information is stored when curation is approved by the curator.
    ///             The protocol and referrer fees are set at the time of lot settlement.
    ///             The fees are cached in order to prevent:
    ///             - Reducing the amount of base tokens available for payout to the winning bidders
    ///             - Reducing the amount of quote tokens available for payment to the seller
    ///
    /// @param      curator     Address of the proposed curator
    /// @param      curated     Whether the curator has approved the auction
    /// @param      curatorFee  The fee charged by the curator
    /// @param      protocolFee The fee charged by the protocol
    /// @param      referrerFee The fee charged by the referrer
    struct FeeData {
        address curator; // 20 bytes
        bool curated; // 1 byte
        uint48 curatorFee; // 6 bytes
        uint48 protocolFee; // 6 bytes
        uint48 referrerFee; // 6 bytes
    }

    /// @notice     Auction routing information provided as input parameters
    /// @dev        After validation, this information is stored in the Routing struct
    ///
    /// @param      auctionType         Auction type, represented by the Keycode for the auction submodule
    /// @param      baseToken           Token provided by seller
    /// @param      quoteToken          Token to accept as payment
    /// @param      curator             (optional) Address of the proposed curator
    /// @param      callbacks           (optional) Callbacks implementation for extended functionality
    /// @param      callbackData        (optional) abi-encoded data to be sent to the onCreate callback function
    /// @param      derivativeType      (optional) Derivative type, represented by the Keycode for the derivative submodule
    /// @param      derivativeParams    (optional) abi-encoded data to be used to create payout derivatives on a purchase. The format of this is dependent on the derivative module.
    /// @param      prefunded           Whether the auction should be pre-funded. Must be true for batch auctions.
    struct RoutingParams {
        Keycode auctionType;
        ERC20 baseToken;
        ERC20 quoteToken;
        address curator;
        ICallback callbacks;
        bytes callbackData;
        Keycode derivativeType;
        bytes derivativeParams;
        bool wrapDerivative;
        bool prefunded;
    }

    // ========= STATE ========== //

    /// @notice     Counter for auction lots
    uint96 public lotCounter;

    /// @notice     Mapping of lot IDs to their auction type (represented by the Keycode for the auction submodule)
    mapping(uint96 lotId => Routing) public lotRouting;

    /// @notice     Mapping of lot IDs to their fee information
    mapping(uint96 lotId => FeeData) public lotFees;

    // ========== AUCTION MANAGEMENT ========== //

    /// @notice     Creates a new auction lot
    /// @dev        The function reverts if:
    ///             - The module for the auction type is not installed
    ///             - The auction type is sunset
    ///             - The base token or quote token decimals are not within the required range
    ///             - The value of `RoutingParams.prefunded` is incorrect for the auction type
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
    /// @param      infoHash_   IPFS hash of the auction information
    /// @return     lotId       ID of the auction lot
    function auction(
        RoutingParams calldata routing_,
        Auction.AuctionParams calldata params_,
        string calldata infoHash_
    ) external nonReentrant returns (uint96 lotId) {
        // Check that the module for the auction type is valid
        // Validate routing parameters

        // Tokens must not be the zero address
        if (address(routing_.baseToken) == address(0) || address(routing_.quoteToken) == address(0))
        {
            revert InvalidParams();
        }

        Routing storage routing = lotRouting[lotId];

        bool requiresPrefunding;
        uint96 lotCapacity;
        {
            // Load auction type module, this checks that it is installed.
            // We load it here vs. later to avoid two checks.
            AuctionModule auctionModule =
                AuctionModule(_getLatestModuleIfActive(routing_.auctionType));

            // Confirm tokens are within the required decimal range
            uint8 baseTokenDecimals = routing_.baseToken.decimals();
            uint8 quoteTokenDecimals = routing_.quoteToken.decimals();

            if (
                auctionModule.TYPE() != Module.Type.Auction || baseTokenDecimals < 6
                    || baseTokenDecimals > 18 || quoteTokenDecimals < 6 || quoteTokenDecimals > 18
            ) revert InvalidParams();

            // Increment lot count and get ID
            lotId = lotCounter++;

            // Call module auction function to store implementation-specific data
            (lotCapacity) =
                auctionModule.auction(lotId, params_, quoteTokenDecimals, baseTokenDecimals);
            routing.auctionReference = auctionModule.VEECODE();

            // Prefunding is required for batch auctions
            // Check that this is not incorrectly overridden
            if (auctionModule.auctionType() == Auction.AuctionType.Batch && !routing_.prefunded) {
                revert InvalidParams();
            }

            requiresPrefunding = routing_.prefunded;
        }

        // Store routing information
        routing.seller = msg.sender;
        routing.baseToken = routing_.baseToken;
        routing.quoteToken = routing_.quoteToken;

        // Store curation information
        {
            FeeData storage fees = lotFees[lotId];
            fees.curator = routing_.curator;
            fees.curated = false;
        }

        // Derivative
        if (fromKeycode(routing_.derivativeType) != bytes5("")) {
            // Load derivative module, this checks that it is installed.
            DerivativeModule derivativeModule =
                DerivativeModule(_getLatestModuleIfActive(routing_.derivativeType));

            // Check that the module for the derivative type is valid
            // Call module validate function to validate implementation-specific data
            if (
                derivativeModule.TYPE() != Module.Type.Derivative
                    || !derivativeModule.validate(address(routing.baseToken), routing_.derivativeParams)
            ) {
                revert InvalidParams();
            }

            // Store derivative information
            routing.derivativeReference = derivativeModule.VEECODE();
            routing.derivativeParams = routing_.derivativeParams;
            routing.wrapDerivative = routing_.wrapDerivative;
        }

        // Validate callbacks address and store if provided
        // This does not check whether the callbacks contract is implemented properly
        // Certain functions may revert later. TODO need to think about security with this.
        if (!Callbacks.isValidCallbacksAddress(routing_.callbacks)) revert InvalidParams();
        // The zero address passes the isValidCallbackAddress check since we allow auctions to not use a callbacks contract
        if (address(routing_.callbacks) != address(0)) routing.callbacks = routing_.callbacks;

        // Perform pre-funding, if needed
        // It does not make sense to pre-fund the auction if the capacity is in quote tokens
        if (requiresPrefunding == true) {
            // Capacity must be in base token for auctions that require pre-funding
            if (params_.capacityInQuote) revert InvalidParams();

            // Store pre-funding information
            routing.funding = lotCapacity;

            // Handle funding from callback or seller as configured
            if (routing_.callbacks.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG)) {
                uint256 balanceBefore = routing_.baseToken.balanceOf(address(this));

                // The onCreate callback should transfer the base token to this contract
                _onCreateCallback(routing_, lotId, lotCapacity, true);

                // Check that the hook transferred the expected amount of base tokens
                if (routing_.baseToken.balanceOf(address(this)) < balanceBefore + lotCapacity) {
                    revert InvalidCallback();
                }
            }
            // Otherwise fallback to a standard ERC20 transfer and then call the onCreate callback
            else {
                Transfer.transferFrom(
                    routing_.baseToken, msg.sender, address(this), lotCapacity, true
                );
                _onCreateCallback(routing_, lotId, lotCapacity, false);
            }
        } else {
            // Call onCreate callback with no prefunding
            _onCreateCallback(routing_, lotId, lotCapacity, false);
        }

        emit AuctionCreated(lotId, routing.auctionReference, infoHash_);
    }

    /// @notice     Cancels an auction lot
    /// @dev        This function performs the following:
    ///             - Checks that the lot ID is valid
    ///             - Checks that caller is the seller
    ///             - Calls the auction module to validate state, update records and determine the amount to be refunded
    ///             - If prefunded, sends the refund of payout tokens to the seller
    ///
    ///             The function reverts if:
    ///             - The lot ID is invalid
    ///             - The caller is not the seller
    ///             - The respective auction module reverts
    ///             - The transfer of payout tokens fails
    ///             - re-entrancy is detected
    ///
    /// @param      lotId_      ID of the auction lot
    function cancel(uint96 lotId_, bytes calldata callbackData_) external nonReentrant {
        // Validation
        _isLotValid(lotId_);

        Routing storage routing = lotRouting[lotId_];

        // Check ownership
        if (msg.sender != routing.seller) revert NotPermitted(msg.sender);

        // Cancel the auction on the module
        _getModuleForId(lotId_).cancelAuction(lotId_);

        // If the auction is prefunded and supported, transfer the remaining capacity to the seller
        if (routing.funding > 0) {
            uint96 funding = routing.funding;

            // Set to 0 before transfer to avoid re-entrancy
            routing.funding = 0;

            // Transfer the base tokens to the appropriate contract
            Transfer.transfer(
                routing.baseToken,
                _getAddressGivenCallbackBaseTokenFlag(routing.callbacks, routing.seller),
                funding,
                false
            );

            // Call the callback to transfer the base token to the owner
            Callbacks.onCancel(
                routing.callbacks,
                lotId_,
                funding,
                routing.callbacks.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG),
                callbackData_
            );
        } else {
            // Call the callback to notify of the cancellation
            Callbacks.onCancel(routing.callbacks, lotId_, 0, false, callbackData_);
        }

        emit AuctionCancelled(lotId_, routing.auctionReference);
    }

    // ========== INTERNAL HELPER FUNCTIONS ========== //

    /// @notice         Gets the module for a given lot ID
    /// @dev            The function assumes:
    ///                 - The lot ID is valid
    ///
    /// @param lotId_   ID of the auction lot
    /// @return         AuctionModule
    function _getModuleForId(uint96 lotId_) internal view returns (AuctionModule) {
        // Load module, will revert if not installed
        return AuctionModule(_getModuleIfInstalled(lotRouting[lotId_].auctionReference));
    }

    /// @notice     Gets the module for a given lot ID
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///             - The module for the auction type is not installed
    ///
    /// @param      lotId_      ID of the auction lot
    function getModuleForId(uint96 lotId_) external view returns (AuctionModule) {
        _isLotValid(lotId_);

        return _getModuleForId(lotId_);
    }

    function _onCreateCallback(
        RoutingParams calldata routing_,
        uint96 lotId_,
        uint96 capacity_,
        bool preFund_
    ) internal {
        Callbacks.onCreate(
            routing_.callbacks,
            lotId_,
            msg.sender,
            address(routing_.baseToken),
            address(routing_.quoteToken),
            capacity_,
            preFund_,
            routing_.callbackData
        );
    }

    function _getAddressGivenCallbackBaseTokenFlag(
        ICallback callbacks_,
        address seller_
    ) internal pure returns (address) {
        return callbacks_.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG)
            ? address(callbacks_)
            : seller_;
    }

    // ========= VALIDATION FUNCTIONS ========= //

    /// @notice     Checks that the lot ID is valid
    /// @dev        Reverts if the lot ID is invalid
    ///
    /// @param      lotId_  ID of the auction lot
    function _isLotValid(uint96 lotId_) internal view {
        if (lotId_ >= lotCounter) revert InvalidLotId(lotId_);
    }
}
