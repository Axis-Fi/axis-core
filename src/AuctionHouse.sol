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

// TODO disbursing fees
}

// TODO define purpose
abstract contract Router is FeeManager {
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

    // ========== CONSTRUCTOR ========== //

    constructor(address protocol_) {
        _PROTOCOL = protocol_;
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

    // ========== FEE MANAGEMENT ========== //

    function setProtocolFee(uint48 protocolFee_) external {
        // TOOD make this permissioned
        protocolFee = protocolFee_;
    }

    function setReferrerFee(address referrer_, uint48 referrerFee_) external {
        // TOOD make this permissioned
        referrerFees[referrer_] = referrerFee_;
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

    error InsufficientBalance(address token_, uint256 requiredAmount_);

    error InsufficientAllowance(address token_, address spender_, uint256 requiredAmount_);

    error UnsupportedToken(address token_);

    error InvalidHook();

    // ========== EVENTS ========== //

    event Purchase(uint256 id, address buyer, address referrer, uint256 amount, uint256 payout);

    // ========== STATE VARIABLES ========== //

    IPermit2 public immutable _PERMIT2;

    // ========== CONSTRUCTOR ========== //

    constructor(address protocol_, address permit2_) Router(protocol_) WithModules(msg.sender) {
        _PERMIT2 = IPermit2(permit2_);
    }

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
    ///             5. Transfers the quote token to the auction owner
    ///             5. Transfers the base token from the auction owner or executes the callback
    ///             6. Transfers the base token to the recipient
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
        returns (uint256 payoutAmount)
    {
        // Load routing data for the lot
        Routing memory routing = lotRouting[params_.lotId];

        // Check if the purchaser is on the allowlist
        if (address(routing.allowlist) != address(0)) {
            if (!routing.allowlist.isAllowed(params_.lotId, msg.sender, bytes(""))) {
                revert NotAuthorized();
            }
        }

        uint256 totalFees = _allocateFees(params_.referrer, routing.quoteToken, params_.amount);
        uint256 amountLessFees = params_.amount - totalFees;

        // Send purchase to auction house and get payout plus any extra output
        bytes memory auctionOutput;
        {
            AuctionModule module = _getModuleForId(params_.lotId);
            (payoutAmount, auctionOutput) =
                module.purchase(params_.lotId, amountLessFees, params_.auctionData);
        }

        // Check that payout is at least minimum amount out
        // @dev Moved the slippage check from the auction to the AuctionHouse to allow different routing and purchase logic
        if (payoutAmount < params_.minAmountOut) revert AmountLessThanMinimum();

        // Collect payment from the purchaser
        _collectPayment(
            params_.lotId,
            params_.amount,
            routing.quoteToken,
            routing.hooks,
            params_.approvalDeadline,
            params_.approvalNonce,
            params_.approvalSignature
        );

        // Send payment to auction owner
        _sendPayment(routing.owner, amountLessFees, routing.quoteToken, routing.hooks);

        // Collect payout from auction owner
        _collectPayout(params_.lotId, amountLessFees, payoutAmount, routing);

        // Send payout to recipient
        _sendPayout(params_.lotId, params_.recipient, payoutAmount, routing, auctionOutput);

        // Emit event
        emit Purchase(params_.lotId, msg.sender, params_.referrer, params_.amount, payoutAmount);
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
    ///             2a. If the lot is a derivative, transfers the payout token to the derivative module
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
    /// @param      paymentAmount_  Amount of quoteToken collected (in native decimals)
    /// @param      payoutAmount_   Amount of payoutToken to collect (in native decimals)
    /// @param      routingParams_  Routing parameters for the lot
    function _collectPayout(
        uint256 lotId_,
        uint256 paymentAmount_,
        uint256 payoutAmount_,
        Routing memory routingParams_
    ) internal {
        // Get the balance of the payout token before the transfer
        uint256 balanceBefore = routingParams_.baseToken.balanceOf(address(this));

        // Call mid hook on hooks contract if provided
        if (address(routingParams_.hooks) != address(0)) {
            // The mid hook is expected to transfer the payout token to this contract
            routingParams_.hooks.mid(lotId_, paymentAmount_, payoutAmount_);

            // Check that the mid hook transferred the expected amount of payout tokens
            if (routingParams_.baseToken.balanceOf(address(this)) < balanceBefore + payoutAmount_) {
                revert InvalidHook();
            }
        }
        // Otherwise fallback to a standard ERC20 transfer
        else {
            // Check that the auction owner has sufficient balance of the payout token
            if (routingParams_.baseToken.balanceOf(routingParams_.owner) < payoutAmount_) {
                revert InsufficientBalance(address(routingParams_.baseToken), payoutAmount_);
            }

            // Check that the auction owner has granted approval to transfer the payout token
            if (
                routingParams_.baseToken.allowance(routingParams_.owner, address(this))
                    < payoutAmount_
            ) {
                revert InsufficientAllowance(
                    address(routingParams_.baseToken), address(this), payoutAmount_
                );
            }

            // Transfer the payout token from the auction owner
            // `safeTransferFrom()` will revert upon failure
            routingParams_.baseToken.safeTransferFrom(
                routingParams_.owner, address(this), payoutAmount_
            );

            // Check that it is not a fee-on-transfer token
            if (routingParams_.baseToken.balanceOf(address(this)) < balanceBefore + payoutAmount_) {
                revert UnsupportedToken(address(routingParams_.baseToken));
            }
        }

        // If the lot is a derivative, transfer the base token as collateral to the derivative module
        if (fromVeecode(routingParams_.derivativeReference) != bytes7("")) {
            // Get the details of the derivative module
            address derivativeModuleAddress =
                _getModuleIfInstalled(routingParams_.derivativeReference);

            // Transfer the base token to the derivative module
            routingParams_.baseToken.safeTransfer(derivativeModuleAddress, payoutAmount_);
        }
    }

    /// @notice     Sends the payout token to the recipient
    /// @dev        This function handles the following:
    ///             1. Sends the payout token from the router to the recipient
    ///             1a. If the lot is a derivative, mints the derivative token to the recipient
    ///             2. Calls the post hook on the hooks contract (if provided)
    ///
    ///             This function assumes that:
    ///             - The payout token has already been transferred to this contract
    ///             - The payout token is supported (e.g. not fee-on-transfer)
    ///
    ///             This function reverts if:
    ///             - The payout token transfer fails
    ///             - The payout token transfer would result in a lesser amount being received
    ///             - The post-hook reverts
    ///             - The post-hook invariant is violated
    ///
    /// @param      lotId_          Lot ID
    /// @param      recipient_      Address to receive payout
    /// @param      payoutAmount_   Amount of payoutToken to send (in native decimals)
    /// @param      routingParams_  Routing parameters for the lot
    /// @param      auctionOutput_  Custom data returned by the auction module
    function _sendPayout(
        uint256 lotId_,
        address recipient_,
        uint256 payoutAmount_,
        Routing memory routingParams_,
        bytes memory auctionOutput_
    ) internal {
        // If no derivative, then the payout is sent directly to the recipient
        if (fromVeecode(routingParams_.derivativeReference) == bytes7("")) {
            // Get the pre-transfer balance
            uint256 balanceBefore = routingParams_.baseToken.balanceOf(recipient_);

            // Send payout token to recipient
            routingParams_.baseToken.safeTransfer(recipient_, payoutAmount_);

            // Check that the recipient received the expected amount of payout tokens
            if (routingParams_.baseToken.balanceOf(recipient_) < balanceBefore + payoutAmount_) {
                revert UnsupportedToken(address(routingParams_.baseToken));
            }
        }
        // Otherwise, send parameters and payout to the derivative to mint to recipient
        else {
            // Get the module for the derivative type
            // We assume that the module type has been checked when the lot was created
            DerivativeModule module =
                DerivativeModule(_getModuleIfInstalled(routingParams_.derivativeReference));

            bytes memory derivativeParams = routingParams_.derivativeParams;

            // Lookup condensor module from combination of auction and derivative types
            // If condenser specified, condense auction output and derivative params before sending to derivative module
            Veecode condenserRef =
                condensers[routingParams_.auctionReference][routingParams_.derivativeReference];
            if (fromVeecode(condenserRef) != bytes7("")) {
                // Get condenser module
                CondenserModule condenser = CondenserModule(_getModuleIfInstalled(condenserRef));

                // Condense auction output and derivative params
                derivativeParams = condenser.condense(auctionOutput_, derivativeParams);
            }

            // Call the module to mint derivative tokens to the recipient
            module.mint(recipient_, derivativeParams, payoutAmount_, routingParams_.wrapDerivative);
        }

        // Call post hook on hooks contract if provided
        if (address(routingParams_.hooks) != address(0)) {
            routingParams_.hooks.post(lotId_, payoutAmount_);
        }
    }

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
