// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {IDerivative} from "src/interfaces/modules/IDerivative.sol";
import {IFeeManager} from "src/interfaces/IFeeManager.sol";

// Internal libraries
import {Transfer} from "src/lib/Transfer.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

// External libraries
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ReentrancyGuard} from "lib/solmate/src/utils/ReentrancyGuard.sol";

// Internal dependencies
import {
    fromKeycode, fromVeecode, keycodeFromVeecode, Keycode, Veecode
} from "src/modules/Keycode.sol";
import {Module, WithModules} from "src/modules/Modules.sol";
import {FeeManager} from "src/bases/FeeManager.sol";

import {AuctionModule} from "src/modules/Auction.sol";
import {DerivativeModule} from "src/modules/Derivative.sol";
import {CondenserModule} from "src/modules/Condenser.sol";

/// @title  AuctionHouse
/// @notice The base AuctionHouse contract defines common structures and functions across auction types (atomic and batch).
///         It defines the following:
///         - Creating new auction lots
///         - Cancelling auction lots
///         - Storing information about how to handle inputs and outputs for auctions ("routing")
abstract contract AuctionHouse is IAuctionHouse, WithModules, ReentrancyGuard, FeeManager {
    using Callbacks for ICallback;

    // ========== STATE ========== //

    /// @notice     Address of the Permit2 contract
    address internal immutable _PERMIT2;

    /// @inheritdoc IAuctionHouse
    uint96 public lotCounter;

    /// @inheritdoc IAuctionHouse
    mapping(uint96 lotId => Routing) public lotRouting;

    /// @inheritdoc IAuctionHouse
    mapping(uint96 lotId => FeeData) public lotFees;

    /// @inheritdoc IAuctionHouse
    mapping(Veecode auctionRef => mapping(Veecode derivativeRef => Veecode condenserRef)) public
        condensers;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address protocol_,
        address permit2_
    ) FeeManager(protocol_) WithModules(owner_) {
        _PERMIT2 = permit2_;
    }

    // ========== AUCTION MANAGEMENT ========== //

    /// @inheritdoc IAuctionHouse
    /// @dev        This function performs the following:
    ///             - Validates the auction parameters
    ///             - Validates the auction module
    ///             - Validates the derivative module (if provided)
    ///             - Validates the callbacks contract (if provided)
    ///             - Stores the auction routing information
    ///             - Calls the auction module to store implementation-specific data
    ///             - Caches the fees for the lot
    ///             - Calls the implementation-specific auction function
    ///             - Calls the onCreate callback (if needed)
    ///
    ///             This function reverts if:
    ///             - The module for the auction type is not installed
    ///             - The auction type is sunset
    ///             - The base token or quote token decimals are not within the required range
    ///             - Validation for the auction parameters fails
    ///             - The module for the optional specified derivative type is not installed
    ///             - Validation for the optional specified derivative type fails
    ///             - Validation for the optional specified callbacks contract fails
    ///             - Re-entrancy is detected
    function auction(
        IAuctionHouse.RoutingParams calldata routing_,
        IAuction.AuctionParams calldata params_,
        string calldata infoHash_
    ) external nonReentrant returns (uint96 lotId) {
        // Check that the module for the auction type is valid
        // Validate routing parameters

        // Tokens must not be the zero address
        if (address(routing_.baseToken) == address(0) || address(routing_.quoteToken) == address(0))
        {
            revert InvalidParams();
        }

        // Increment lot count and get ID
        lotId = lotCounter++;

        // Store routing information
        Routing storage routing = lotRouting[lotId];
        routing.seller = msg.sender;
        routing.baseToken = ERC20(routing_.baseToken);
        routing.quoteToken = ERC20(routing_.quoteToken);

        {
            // Load auction type module, this checks that it is installed.
            // We load it here vs. later to avoid two checks.
            AuctionModule auctionModule =
                AuctionModule(_getLatestModuleIfActive(routing_.auctionType));

            // Confirm tokens are within the required decimal range
            uint8 baseTokenDecimals = routing.baseToken.decimals();
            uint8 quoteTokenDecimals = routing.quoteToken.decimals();

            if (
                auctionModule.TYPE() != Module.Type.Auction || baseTokenDecimals < 6
                    || baseTokenDecimals > 18 || quoteTokenDecimals < 6 || quoteTokenDecimals > 18
            ) revert InvalidParams();

            // Call module auction function to store implementation-specific data
            auctionModule.auction(lotId, params_, quoteTokenDecimals, baseTokenDecimals);
            routing.auctionReference = auctionModule.VEECODE();
        }

        // Store fee information from params and snapshot fees for the lot
        {
            FeeData storage lotFee = lotFees[lotId];
            lotFee.curator = routing_.curator;
            lotFee.curated = false;

            Fees storage auctionFees = fees[routing_.auctionType];

            // Check that the curator's configured fee does not exceed the protocol max
            // If it does, set the fee to the max
            uint48 maxCuratorFee = auctionFees.maxCuratorFee;
            uint48 curatorFee = auctionFees.curator[routing_.curator];
            lotFee.curatorFee = curatorFee > maxCuratorFee ? maxCuratorFee : curatorFee;

            // Snapshot the protocol and referrer fees
            lotFee.protocolFee = auctionFees.protocol;
            lotFee.referrerFee = auctionFees.referrer;
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

        // Condenser
        {
            // Get condenser reference
            Veecode condenserRef = condensers[routing.auctionReference][routing.derivativeReference];

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

        // Validate callbacks address and store if provided
        // This does not check whether the callbacks contract is implemented properly
        // Certain functions may revert later.
        if (!Callbacks.isValidCallbacksAddress(routing_.callbacks)) revert InvalidParams();
        // The zero address passes the isValidCallbackAddress check since we allow auctions to not use a callbacks contract
        if (address(routing_.callbacks) != address(0)) routing.callbacks = routing_.callbacks;

        // Perform auction-type specific validation and setup
        bool performedCallback = _auction(lotId, routing_, params_);

        // Call the onCreate callback with no prefunding if not already called
        if (!performedCallback) {
            _onCreateCallback(routing_, lotId, params_.capacity, false);
        }

        // Emit auction created event
        emit AuctionCreated(lotId, routing.auctionReference, infoHash_);
    }

    /// @notice     Implementation-specific logic for auction creation
    /// @dev        Inheriting contracts can implement additional logic, such as:
    ///             - Validation
    ///             - Prefunding
    ///
    /// @param      lotId_              The auction lot ID
    /// @param      routing_            RoutingParams
    /// @param      params_             AuctionParams
    /// @return     performedCallback   `true` if the implementing function calls the `onCreate` callback
    function _auction(
        uint96 lotId_,
        IAuctionHouse.RoutingParams calldata routing_,
        IAuction.AuctionParams calldata params_
    ) internal virtual returns (bool performedCallback);

    /// @notice     Cancels an auction lot
    /// @dev        This function performs the following:
    ///             - Checks that the lot ID is valid
    ///             - Checks that caller is the seller
    ///             - Calls the auction module to validate state, update records and determine the amount to be refunded
    ///             - Calls the implementation-specific logic for auction cancellation
    ///             - Calls the onCancel callback (if needed)
    ///
    ///             The function reverts if:
    ///             - The lot ID is invalid
    ///             - The caller is not the seller
    ///             - The respective auction module reverts
    ///             - Re-entrancy is detected
    ///
    /// @param      lotId_      ID of the auction lot
    function cancel(uint96 lotId_, bytes calldata callbackData_) external nonReentrant {
        // Validation
        _isLotValid(lotId_);

        Routing storage routing = lotRouting[lotId_];

        // Check ownership
        if (msg.sender != routing.seller) revert NotPermitted(msg.sender);

        // Cancel the auction on the module
        _getAuctionModuleForId(lotId_).cancelAuction(lotId_);

        // Call the implementation logic
        bool performedCallback = _cancel(lotId_, callbackData_);

        // Call the onCancel callback with no prefunding if not already called
        if (!performedCallback) {
            // Call the callback to notify of the cancellation
            Callbacks.onCancel(routing.callbacks, lotId_, 0, false, callbackData_);
        }

        emit AuctionCancelled(lotId_, routing.auctionReference);
    }

    /// @notice     Implementation-specific logic for auction cancellation
    /// @dev        Inheriting contracts can implement additional logic, such as:
    ///             - Validation
    ///             - Refunding
    ///
    /// @param      lotId_              The auction lot ID
    /// @param      callbackData_       Calldata for the callback
    /// @return     performedCallback   `true` if the implementing function calls the `onCancel` callback
    function _cancel(
        uint96 lotId_,
        bytes calldata callbackData_
    ) internal virtual returns (bool performedCallback);

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IAuctionHouse
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///             - The module for the auction type is not installed
    function getAuctionModuleForId(uint96 lotId_) external view override returns (IAuction) {
        _isLotValid(lotId_);

        return _getAuctionModuleForId(lotId_);
    }

    /// @inheritdoc IAuctionHouse
    /// @dev        The function reverts if:
    ///             - The lot ID is invalid
    ///             - The module for the derivative type is not installed
    function getDerivativeModuleForId(uint96 lotId_) external view override returns (IDerivative) {
        _isLotValid(lotId_);

        return _getDerivativeModuleForId(lotId_);
    }

    // ========== INTERNAL HELPER FUNCTIONS ========== //

    /// @notice         Gets the module for a given lot ID
    /// @dev            The function assumes:
    ///                 - The lot ID is valid
    ///
    /// @param lotId_   ID of the auction lot
    /// @return         AuctionModule
    function _getAuctionModuleForId(uint96 lotId_) internal view returns (AuctionModule) {
        // Load module, will revert if not installed
        return AuctionModule(_getModuleIfInstalled(lotRouting[lotId_].auctionReference));
    }

    /// @notice         Gets the module for a given lot ID
    /// @dev            The function assumes:
    ///                 - The lot ID is valid
    ///
    /// @param lotId_   ID of the auction lot
    /// @return         DerivativeModule
    function _getDerivativeModuleForId(uint96 lotId_) internal view returns (DerivativeModule) {
        // Load module, will revert if not installed. Also reverts if no derivative is specified.
        return DerivativeModule(_getModuleIfInstalled(lotRouting[lotId_].derivativeReference));
    }

    function _onCreateCallback(
        IAuctionHouse.RoutingParams calldata routing_,
        uint96 lotId_,
        uint256 capacity_,
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

    // ========== CURATION ========== //

    /// @notice     Accept curation request for a lot.
    /// @notice     If the curator wishes to charge a fee, it must be set before this function is called.
    /// @notice     Access controlled. Must be proposed curator for lot.
    /// @dev        This function performs the following:
    ///             - Checks that the lot ID is valid
    ///             - Checks that the caller is the proposed curator
    ///             - Validates state
    ///             - Sets the curated state to true
    ///             - Calls the implementation-specific logic for curation
    ///             - Calls the onCurate callback (if needed)
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The caller is not the proposed curator
    ///             - The auction has ended or is already curated
    ///             - Re-entrancy is detected
    ///
    /// @param     lotId_       Lot ID
    function curate(uint96 lotId_, bytes calldata callbackData_) external nonReentrant {
        _isLotValid(lotId_);

        FeeData storage feeData = lotFees[lotId_];

        // Check that the caller is the proposed curator
        if (msg.sender != feeData.curator) revert NotPermitted(msg.sender);

        AuctionModule module = _getAuctionModuleForId(lotId_);

        // Check that the curator has not already approved the auction
        // Check that the auction has not ended or been cancelled
        if (feeData.curated || module.hasEnded(lotId_) == true) revert InvalidState();

        Routing storage routing = lotRouting[lotId_];

        // Set the curator as approved
        feeData.curated = true;

        // Calculate the fee amount based on the remaining capacity (must be in base token if auction is pre-funded)
        uint256 curatorFeePayout = _calculatePayoutFees(
            feeData.curated, feeData.curatorFee, module.remainingCapacity(lotId_)
        );

        // Call the implementation-specific logic
        (bool performedCallback) = _curate(lotId_, curatorFeePayout, callbackData_);

        // Call onCurate if necessary
        if (!performedCallback) {
            Callbacks.onCurate(routing.callbacks, lotId_, curatorFeePayout, false, callbackData_);
        }

        // Emit event that the lot is curated by the proposed curator
        emit Curated(lotId_, msg.sender);
    }

    /// @notice     Implementation-specific logic for curation
    /// @dev        Inheriting contracts can implement additional logic, such as:
    ///             - Validation
    ///             - Prefunding
    ///
    /// @param      lotId_              The auction lot ID
    /// @param      curatorFeePayout_   The amount to pay the curator
    /// @param      callbackData_       Calldata for the callback
    /// @return     performedCallback   `true` if the implementing function calls the `onCurate` callback
    function _curate(
        uint96 lotId_,
        uint256 curatorFeePayout_,
        bytes calldata callbackData_
    ) internal virtual returns (bool performedCallback);

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IFeeManager
    /// @dev        Implemented in this contract as it required access to the `onlyOwner` modifier
    function setFee(Keycode auctionType_, FeeType type_, uint48 fee_) external override onlyOwner {
        // Check that the fee is a valid percentage
        if (fee_ > _FEE_DECIMALS) revert InvalidFee();

        // Set fee based on type
        // Or a combination of protocol and referrer fee since they are both in the quoteToken?
        if (type_ == FeeType.Protocol) {
            fees[auctionType_].protocol = fee_;
        } else if (type_ == FeeType.Referrer) {
            fees[auctionType_].referrer = fee_;
        } else if (type_ == FeeType.MaxCurator) {
            fees[auctionType_].maxCuratorFee = fee_;
        }
    }

    /// @inheritdoc IFeeManager
    /// @dev        Implemented in this contract as it required access to the `onlyOwner` modifier
    function setProtocol(address protocol_) external override onlyOwner {
        _protocol = protocol_;
    }

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

    // ========== TOKEN TRANSFERS ========== //

    /// @notice     Convenience function to collect payment of the quote token from the user
    /// @dev        This function calls the Transfer library to handle the transfer of the quote token
    ///
    /// @param      amount_             Amount of quoteToken to collect (in native decimals)
    /// @param      quoteToken_         Quote token to collect
    /// @param      permit2Approval_    Permit2 approval data (optional)
    function _collectPayment(
        uint256 amount_,
        ERC20 quoteToken_,
        Transfer.Permit2Approval memory permit2Approval_
    ) internal {
        Transfer.permit2OrTransferFrom(
            quoteToken_, _PERMIT2, msg.sender, address(this), amount_, permit2Approval_, true
        );
    }

    /// @notice     Convenience function to send payment of the quote token to the seller
    /// @dev        This function calls the Transfer library to handle the transfer of the quote token
    ///
    /// @param      lotOwner_       Owner of the lot
    /// @param      amount_         Amount of quoteToken to send (in native decimals)
    /// @param      quoteToken_     Quote token to send
    /// @param      callbacks_      Callbacks contract that may receive the tokens
    function _sendPayment(
        address lotOwner_,
        uint256 amount_,
        ERC20 quoteToken_,
        ICallback callbacks_
    ) internal {
        // Determine where to send the payment
        address to = callbacks_.hasPermission(Callbacks.RECEIVE_QUOTE_TOKENS_FLAG)
            ? address(callbacks_)
            : lotOwner_;

        // Send the payment
        Transfer.transfer(quoteToken_, to, amount_, false);
    }

    /// @notice     Sends the payout token to the recipient
    /// @dev        This function handles the following:
    ///             - If the lot has a derivative defined, mints the derivative token ot the recipient
    ///             - Otherwise, sends the payout token to the recipient
    ///
    ///             This function assumes that:
    ///             - The payout token has already been transferred to this contract
    ///             - The payout token is supported (e.g. not fee-on-transfer)
    ///
    ///             This function reverts if:
    ///             - The payout token transfer fails
    ///             - The payout token transfer would result in a lesser amount being received
    ///
    /// @param      recipient_      Address to receive payout
    /// @param      payoutAmount_   Amount of payoutToken to send (in native decimals)
    /// @param      routingParams_  Routing parameters for the lot
    /// @param      auctionOutput_  Output data from the auction module
    function _sendPayout(
        address recipient_,
        uint256 payoutAmount_,
        Routing memory routingParams_,
        bytes memory auctionOutput_
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

            bytes memory derivativeParams = routingParams_.derivativeParams;

            // Lookup condenser module from combination of auction and derivative types
            // If condenser specified, condense auction output and derivative params before sending to derivative module
            Veecode condenserRef = condensers[routingParams_.auctionReference][derivativeReference];
            if (fromVeecode(condenserRef) != bytes7("")) {
                // Get condenser module
                CondenserModule condenser = CondenserModule(_getModuleIfInstalled(condenserRef));

                // Condense auction output and derivative params
                derivativeParams = condenser.condense(auctionOutput_, derivativeParams);
            }

            // Approve the module to transfer payout tokens when minting
            Transfer.approve(baseToken, address(module), payoutAmount_);

            // Call the module to mint derivative tokens to the recipient
            module.mint(
                recipient_,
                address(baseToken),
                derivativeParams,
                payoutAmount_,
                routingParams_.wrapDerivative
            );
        }
    }

    // ========== FEE FUNCTIONS ========== //

    /// @notice  Allocates fees on quote tokens to the protocol and referrer
    /// @dev     This function calculates the fees for the quote token and updates the balances.
    ///
    /// @param   protocolFee_   The fee charged by the protocol
    /// @param   referrerFee_   The fee charged by the referrer
    /// @param   referrer_      The address of the referrer
    /// @param   seller_        The address of the seller
    /// @param   quoteToken_    The quote token
    /// @param   amount_        The amount of quote tokens
    function _allocateQuoteFees(
        uint48 protocolFee_,
        uint48 referrerFee_,
        address referrer_,
        address seller_,
        ERC20 quoteToken_,
        uint256 amount_
    ) internal returns (uint256 totalFees) {
        // Calculate fees for purchase
        (uint256 toReferrer, uint256 toProtocol) = calculateQuoteFees(
            protocolFee_, referrerFee_, referrer_ != address(0) && referrer_ != seller_, amount_
        );

        // Update fee balances if non-zero
        if (toReferrer > 0) rewards[referrer_][quoteToken_] += toReferrer;
        if (toProtocol > 0) rewards[_protocol][quoteToken_] += toProtocol;

        return toReferrer + toProtocol;
    }
}
