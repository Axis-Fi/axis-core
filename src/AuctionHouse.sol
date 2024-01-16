/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

import {IPermit2} from "src/lib/permit2/interfaces/IPermit2.sol";

import {Auctioneer} from "src/bases/Auctioneer.sol";
import {CondenserModule} from "src/modules/Condenser.sol";

import {Derivatizer} from "src/bases/Derivatizer.sol";
import {DerivativeModule} from "src/modules/Derivative.sol";

import {Auction, AuctionModule} from "src/modules/Auction.sol";

import {Veecode, fromVeecode, WithModules} from "src/modules/Modules.sol";

import {IHooks} from "src/interfaces/IHooks.sol";

// TODO define purpose
abstract contract FeeManager {
// TODO write fee logic in separate contract to keep it organized
// Router can inherit
}

// TODO define purpose
abstract contract Router is FeeManager {
    using SafeTransferLib for ERC20;

    // ========== ERRORS ========== //

    error InsufficientBalance(address token_, uint256 requiredAmount_);

    error InsufficientAllowance(address token_, address spender_, uint256 requiredAmount_);

    error UnsupportedToken(address token_);

    error InvalidHook();

    // ========== STRUCTS ========== //

    /// @notice     Parameters used by the purchase function
    /// @dev        This reduces the number of variables in scope for the purchase function
    ///
    /// @param      recipient           Address to receive payout
    /// @param      referrer            Address of referrer
    /// @param      approvalDeadline    Deadline for approval signature
    /// @param      lotId               Lot ID
    /// @param      amount              Amount of quoteToken to purchase with (in native decimals)
    /// @param      minAmountOut        Minimum amount of baseToken to receive
    /// @param      approvalNonce       Nonce for permit approval signature
    /// @param      auctionData         Custom data used by the auction module
    /// @param      approvalSignature   Permit approval signature for the quoteToken
    struct PurchaseParams {
        address recipient;
        address referrer;
        uint48 approvalDeadline;
        uint256 lotId;
        uint256 amount;
        uint256 minAmountOut;
        uint256 approvalNonce;
        bytes auctionData;
        bytes approvalSignature;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice Fee paid to a front end operator in basis points (3 decimals). Set by the referrer, must be less than or equal to 5% (5e3).
    /// @dev There are some situations where the fees may round down to zero if quantity of baseToken
    ///      is < 1e5 wei (can happen with big price differences on small decimal tokens). This is purely
    ///      a theoretical edge case, as the bond amount would not be practical.
    mapping(address => uint48) public referrerFees;

    // TODO allow charging fees based on the auction type and/or derivative type
    /// @notice Fee paid to protocol in basis points (3 decimal places).
    uint48 public protocolFee;

    /// @notice 'Create' function fee discount in basis points (3 decimal places). Amount standard fee is reduced by for partners who just want to use the 'create' function to issue bond tokens.
    uint48 public createFeeDiscount;

    uint48 public constant FEE_DECIMALS = 1e5; // one percent equals 1000.

    /// @notice Fees earned by an address, by token
    mapping(address => mapping(ERC20 => uint256)) public rewards;

    // Address the protocol receives fees at
    // TODO make this updatable
    address internal immutable _PROTOCOL;

    IPermit2 public immutable _PERMIT2;

    // ========== CONSTRUCTOR ========== //

    constructor(address protocol_, address permit2_) {
        _PROTOCOL = protocol_;
        _PERMIT2 = IPermit2(permit2_);
    }

    // ========== ATOMIC AUCTIONS ========== //

    /// @notice     Purchase a lot from an auction
    /// @notice     Permit2 is utilised to simplify token transfers
    ///
    /// @param      params_         Purchase parameters
    /// @return     payout          Amount of baseToken received by `recipient_` (in native decimals)
    function purchase(PurchaseParams memory params_) external virtual returns (uint256 payout);

    // ========== BATCH AUCTIONS ========== //

    // On-chain auction variant
    function bid(
        address recipient_,
        address referrer_,
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_,
        bytes calldata auctionData_,
        bytes calldata approval_
    ) external virtual;

    function settle(uint256 id_) external virtual returns (uint256[] memory amountsOut);

    // Off-chain auction variant
    function settle(
        uint256 id_,
        Auction.Bid[] memory bids_
    ) external virtual returns (uint256[] memory amountsOut);

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
    /// @param      approvalDeadline_   Deadline for Permit2 approval signature
    /// @param      approvalNonce_      Nonce for Permit2 approval signature
    /// @param      approvalSignature_  Permit2 approval signature for the quoteToken
    function _collectPayment(
        uint256 lotId_,
        uint256 amount_,
        ERC20 quoteToken_,
        IHooks hooks_,
        uint48 approvalDeadline_,
        uint256 approvalNonce_,
        bytes memory approvalSignature_
    ) internal {
        // Call pre hook on hooks contract if provided
        if (address(hooks_) != address(0)) {
            hooks_.pre(lotId_, amount_);
        }

        // Check that the user has sufficient balance of the quote token
        if (quoteToken_.balanceOf(msg.sender) < amount_) {
            revert InsufficientBalance(address(quoteToken_), amount_);
        }

        // If a Permit2 approval signature is provided, use it to transfer the quote token
        if (approvalSignature_.length != 0) {
            _permit2Transfer(
                amount_, quoteToken_, approvalDeadline_, approvalNonce_, approvalSignature_
            );
        }
        // Otherwise fallback to a standard ERC20 transfer
        else {
            _transfer(amount_, quoteToken_);
        }
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
        if (address(hooks_) != address(0)) {
            // Send quote token to hooks contract
            quoteToken_.safeTransfer(address(hooks_), amount_);
        } else {
            // Send quote token to auction owner
            quoteToken_.safeTransfer(lotOwner_, amount_);
        }
    }

    /// @notice     Collects the payout token from the auction owner
    /// @dev        This function handles the following:
    ///             1. Calls the mid hook on the hooks contract (if provided)
    ///             2. Transfers the payout token from the auction owner
    ///
    ///             This function reverts if:
    ///             - Approval has not been granted to transfer the payout token
    ///             - The auction owner does not have sufficient balance of the payout token
    ///             - The payout token transfer fails
    ///             - Transferring the payout token would result in a lesser amount being received
    ///             - The mid-hook reverts
    ///             - The mid-hook invariant is violated
    ///
    /// @param      lotId_          Lot ID
    /// @param      lotOwner_       Owner of the lot
    /// @param      paymentAmount_  Amount of quoteToken collected (in native decimals)
    /// @param      payoutAmount_   Amount of payoutToken to collect (in native decimals)
    /// @param      payoutToken_    Payout token to collect
    /// @param      hooks_          Hooks contract to call (optional)
    function _collectPayout(
        uint256 lotId_,
        address lotOwner_,
        uint256 paymentAmount_,
        uint256 payoutAmount_,
        ERC20 payoutToken_,
        IHooks hooks_
    ) internal {
        // Get the balance of the payout token before the transfer
        uint256 balanceBefore = payoutToken_.balanceOf(address(this));

        // Call mid hook on hooks contract if provided
        if (address(hooks_) != address(0)) {
            // The mid hook is expected to transfer the payout token to this contract
            hooks_.mid(lotId_, paymentAmount_, payoutAmount_);

            // Check that the mid hook transferred the expected amount of payout tokens
            if (payoutToken_.balanceOf(address(this)) < balanceBefore + payoutAmount_) {
                revert InvalidHook();
            }
        }
        // Otherwise fallback to a standard ERC20 transfer
        else {
            // Check that the auction owner has sufficient balance of the payout token
            if (payoutToken_.balanceOf(lotOwner_) < payoutAmount_) {
                revert InsufficientBalance(address(payoutToken_), payoutAmount_);
            }

            // Check that the auction owner has granted approval to transfer the payout token
            if (payoutToken_.allowance(lotOwner_, address(this)) < payoutAmount_) {
                revert InsufficientAllowance(address(payoutToken_), address(this), payoutAmount_);
            }

            // Transfer the payout token from the auction owner
            // `safeTransferFrom()` will revert upon failure
            payoutToken_.safeTransferFrom(lotOwner_, address(this), payoutAmount_);

            // Check that it is not a fee-on-transfer token
            if (payoutToken_.balanceOf(address(this)) < balanceBefore + payoutAmount_) {
                revert UnsupportedToken(address(payoutToken_));
            }
        }

        // TODO handle derivative
    }

    // TODO sendPayout

    // TODO sendPayment

    /// @notice     Performs an ERC20 transfer of `token_` from the caller
    /// @dev        This function handles the following:
    ///             1. Checks that the user has granted approval to transfer the token
    ///             2. Transfers the token from the user
    ///             3. Checks that the transferred amount was received
    ///
    ///             This function reverts if:
    ///             - Approval has not been granted to this contract to transfer the token
    ///             - The token transfer fails
    ///             - The transferred amount is less than the requested amount
    ///
    /// @param      amount_   Amount of tokens to transfer (in native decimals)
    /// @param      token_    Token to transfer
    function _transfer(uint256 amount_, ERC20 token_) internal {
        // Check that the user has granted approval to transfer the quote token
        if (token_.allowance(msg.sender, address(this)) < amount_) {
            revert InsufficientAllowance(address(token_), address(this), amount_);
        }

        uint256 balanceBefore = token_.balanceOf(address(this));

        // Transfer the quote token from the user
        // `safeTransferFrom()` will revert upon failure
        token_.safeTransferFrom(msg.sender, address(this), amount_);

        // Check that it is not a fee-on-transfer token
        if (token_.balanceOf(address(this)) < balanceBefore + amount_) {
            revert UnsupportedToken(address(token_));
        }
    }

    /// @notice     Performs a Permit2 transfer of `token_` from the caller
    /// @dev        This function handles the following:
    ///             1. Checks that the user has granted approval to transfer the token
    ///             2. Uses Permit2 to transfer the token from the user
    ///             3. Checks that the transferred amount was received
    ///
    ///             This function reverts if:
    ///             - Approval has not been granted to Permit2 to transfer the token
    ///             - The Permit2 transfer (or signature validation) fails
    ///             - The transferred amount is less than the requested amount
    ///
    /// @param      amount_               Amount of tokens to transfer (in native decimals)
    /// @param      token_                Token to transfer
    /// @param      approvalDeadline_     Deadline for Permit2 approval signature
    /// @param      approvalNonce_        Nonce for Permit2 approval signature
    /// @param      approvalSignature_    Permit2 approval signature for the token
    function _permit2Transfer(
        uint256 amount_,
        ERC20 token_,
        uint48 approvalDeadline_,
        uint256 approvalNonce_,
        bytes memory approvalSignature_
    ) internal {
        // Check that the user has granted approval to PERMIT2 to transfer the quote token
        if (token_.allowance(msg.sender, address(_PERMIT2)) < amount_) {
            revert InsufficientAllowance(address(token_), address(_PERMIT2), amount_);
        }

        uint256 balanceBefore = token_.balanceOf(address(this));

        // Use PERMIT2 to transfer the token from the user
        _PERMIT2.permitTransferFrom(
            IPermit2.PermitTransferFrom(
                IPermit2.TokenPermissions(address(token_), amount_),
                approvalNonce_,
                approvalDeadline_
            ),
            IPermit2.SignatureTransferDetails({to: address(this), requestedAmount: amount_}),
            msg.sender, // Spender of the tokens
            approvalSignature_
        );

        // Check that it is not a fee-on-transfer token
        if (token_.balanceOf(address(this)) < balanceBefore + amount_) {
            revert UnsupportedToken(address(token_));
        }
    }
}

/// @title      AuctionHouse
/// @notice     As its name implies, the AuctionHouse is where auctions take place and the core of the protocol.
contract AuctionHouse is Derivatizer, Auctioneer, Router {
    using SafeTransferLib for ERC20;

    /// Implement the router functionality here since it combines all of the base functionality

    // ========== ERRORS ========== //
    error AmountLessThanMinimum();

    error NotAuthorized();

    // ========== EVENTS ========== //
    event Purchase(uint256 id, address buyer, address referrer, uint256 amount, uint256 payout);

    // ========== CONSTRUCTOR ========== //
    constructor(
        address protocol_,
        address permit2_
    ) Router(protocol_, permit2_) WithModules(msg.sender) {}

    // ========== DIRECT EXECUTION ========== //

    // ========== AUCTION FUNCTIONS ========== //

    function _allocateFees(
        address referrer_,
        ERC20 quoteToken_,
        uint256 amount_
    ) internal returns (uint256 totalFees) {
        // TODO should protocol and/or referrer be able to charge different fees based on the type of auction being used?

        // Calculate fees for purchase
        // 1. Calculate referrer fee
        // 2. Calculate protocol fee as the total expected fee amount minus the referrer fee
        //    to avoid issues with rounding from separate fee calculations
        uint256 toReferrer;
        uint256 toProtocol;
        if (referrer_ == address(0)) {
            // There is no referrer
            toProtocol = (amount_ * protocolFee) / FEE_DECIMALS;
        } else {
            uint256 referrerFee = referrerFees[referrer_]; // reduce to single SLOAD
            if (referrerFee == 0) {
                // There is a referrer, but they have not set a fee
                // If protocol fee is zero, return zero
                // Otherwise, calcualte protocol fee
                if (protocolFee == 0) return 0;
                toProtocol = (amount_ * protocolFee) / FEE_DECIMALS;
            } else {
                // There is a referrer and they have set a fee
                toReferrer = (amount_ * referrerFee) / FEE_DECIMALS;
                toProtocol = ((amount_ * (protocolFee + referrerFee)) / FEE_DECIMALS) - toReferrer;
            }
        }

        // Update fee balances if non-zero
        if (toReferrer > 0) rewards[referrer_][quoteToken_] += toReferrer;
        if (toProtocol > 0) rewards[_PROTOCOL][quoteToken_] += toProtocol;

        return toReferrer + toProtocol;
    }

    // ========== ATOMIC AUCTIONS ========== //

    /// @inheritdoc Router
    /// @dev        This fuction handles the following:
    ///             1. Calculates the fees for the purchase
    ///             2. Sends the purchase amount to the auction module
    ///             3. Records the purchase on the auction module
    ///             4. Transfers the quote token from the caller
    ///             5. Transfers the quote token to the auction owner or executes the callback
    ///             6. Transfers the payout token to the recipient
    ///
    ///             This function reverts if:
    ///             - `lotId_` is invalid
    ///             - The respective auction module reverts
    ///             - `payout` is less than `minAmountOut_`
    ///             - The caller does not have sufficient balance of the quote token
    ///             - The auction owner does not have sufficient balance of the payout token
    ///             - Any of the callbacks fail
    ///             - Any of the token transfers fail
    function purchase(PurchaseParams memory params_)
        external
        override
        isValidLot(params_.lotId)
        returns (uint256 payout)
    {
        // TODO should this not check if the auction is atomic?
        // Response: No, my thought was that the module will just revert on `purchase` if it's not atomic. Vice versa

        // Load routing data for the lot
        Routing memory routing = lotRouting[params_.lotId];

        uint256 totalFees = _allocateFees(params_.referrer, routing.quoteToken, params_.amount);

        // Send purchase to auction house and get payout plus any extra output
        bytes memory auctionOutput;
        {
            AuctionModule module = _getModuleForId(params_.lotId);
            (payout, auctionOutput) =
                module.purchase(params_.lotId, params_.amount - totalFees, params_.auctionData);
        }

        // Check that payout is at least minimum amount out
        // @dev Moved the slippage check from the auction to the AuctionHouse to allow different routing and purchase logic
        if (payout < params_.minAmountOut) revert AmountLessThanMinimum();

        // Handle transfers from purchaser and seller
        _handleTransfers(
            params_.lotId, routing, params_.amount, payout, totalFees, params_.approvalSignature
        );

        // Handle payout to user, including creation of derivative tokens
        _handlePayout(routing, params_.recipient, payout, auctionOutput);

        // Emit event
        emit Purchase(params_.lotId, msg.sender, params_.referrer, params_.amount, payout);
    }

    // ========== BATCH AUCTIONS ========== //

    function bid(
        address recipient_,
        address referrer_,
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_,
        bytes calldata auctionData_,
        bytes calldata approval_
    ) external override {
        // TODO
    }

    function settle(uint256 id_) external override returns (uint256[] memory amountsOut) {
        // TODO
    }

    // Off-chain auction variant
    function settle(
        uint256 id_,
        Auction.Bid[] memory bids_
    ) external override returns (uint256[] memory amountsOut) {
        // TODO
    }

    // ============ INTERNAL EXECUTION FUNCTIONS ========== //

    /// @notice     Handles transfer of funds from user and market owner/callback
    function _handleTransfers(
        uint256 id_,
        Routing memory routing_,
        uint256 amount_,
        uint256 payout_,
        uint256 feePaid_,
        bytes memory approval_
    ) internal {
        // Calculate amount net of fees
        uint256 amountLessFee = amount_ - feePaid_;

        // Check if approval signature has been provided, if so use it increase allowance
        // TODO a bunch of extra data has to be provided for Permit.
        if (approval_.length != 0) {}

        // Have to transfer to teller first since fee is in quote token
        // Check balance before and after to ensure full amount received, revert if not
        // Handles edge cases like fee-on-transfer tokens (which are not supported)
        uint256 quoteBalance = routing_.quoteToken.balanceOf(address(this));
        routing_.quoteToken.safeTransferFrom(msg.sender, address(this), amount_);
        if (routing_.quoteToken.balanceOf(address(this)) < quoteBalance + amount_) {
            revert UnsupportedToken(address(routing_.quoteToken));
        }

        // If callback address supplied, transfer tokens from teller to callback, then execute callback function,
        // and ensure proper amount of tokens transferred in.
        // TODO substitute callback for hooks (and implement in more places)?
        if (address(routing_.hooks) != address(0)) {
            // Send quote token to callback (transferred in first to allow use during callback)
            routing_.quoteToken.safeTransfer(address(routing_.hooks), amountLessFee);

            // Call the callback function to receive payout tokens for payout
            uint256 baseBalance = routing_.baseToken.balanceOf(address(this));
            routing_.hooks.mid(id_, amountLessFee, payout_);

            // Check to ensure that the callback sent the requested amount of payout tokens back to the teller
            if (routing_.baseToken.balanceOf(address(this)) < (baseBalance + payout_)) {
                revert InvalidHook();
            }
        } else {
            // If no callback is provided, transfer tokens from market owner to this contract
            // for payout.
            // Check balance before and after to ensure full amount received, revert if not
            // Handles edge cases like fee-on-transfer tokens (which are not supported)
            uint256 baseBalance = routing_.baseToken.balanceOf(address(this));
            routing_.baseToken.safeTransferFrom(routing_.owner, address(this), payout_);
            if (routing_.baseToken.balanceOf(address(this)) < (baseBalance + payout_)) {
                revert UnsupportedToken(address(routing_.baseToken));
            }

            routing_.quoteToken.safeTransfer(routing_.owner, amountLessFee);
        }
    }

    function _handlePayout(
        Routing memory routing_,
        address recipient_,
        uint256 payout_,
        bytes memory auctionOutput_
    ) internal {
        // If no derivative, then the payout is sent directly to the recipient
        // Otherwise, send parameters and payout to the derivative to mint to recipient
        if (fromVeecode(routing_.derivativeReference) == bytes7("")) {
            // No derivative, send payout to recipient
            routing_.baseToken.safeTransfer(recipient_, payout_);
        } else {
            // Get the module for the derivative type
            // We assume that the module type has been checked when the lot was created
            DerivativeModule module =
                DerivativeModule(_getModuleIfInstalled(routing_.derivativeReference));

            bytes memory derivativeParams = routing_.derivativeParams;

            // Lookup condensor module from combination of auction and derivative types
            // If condenser specified, condense auction output and derivative params before sending to derivative module
            Veecode condenserRef =
                condensers[routing_.auctionReference][routing_.derivativeReference];
            if (fromVeecode(condenserRef) != bytes7("")) {
                // Get condenser module
                CondenserModule condenser = CondenserModule(_getModuleIfInstalled(condenserRef));

                // Condense auction output and derivative params
                derivativeParams = condenser.condense(auctionOutput_, derivativeParams);
            }

            // Approve the module to transfer payout tokens
            routing_.baseToken.safeApprove(address(module), payout_);

            // Call the module to mint derivative tokens to the recipient
            module.mint(recipient_, derivativeParams, payout_, routing_.wrapDerivative);
        }
    }
}
