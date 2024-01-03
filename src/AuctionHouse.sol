/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

import "src/bases/Derivatizer.sol";
import "src/bases/Auctioneer.sol";
import "src/modules/Condenser.sol";

abstract contract FeeManager {
    // TODO write fee logic in separate contract to keep it organized
    // Router can inherit
}

abstract contract Router is FeeManager {

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
    address internal immutable _protocol;

    // ========== CONSTRUCTOR ========== //

    constructor(address protocol_) {
        _protocol = protocol_;
    }

    // ========== ATOMIC AUCTIONS ========== //

    /// @param approval_ - (Optional) Permit approval signature for the quoteToken
    function purchase(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_) external virtual returns (uint256 payout);

    // ========== BATCH AUCTIONS ========== //

    // On-chain auction variant
    function bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_) external virtual;

    function settle(uint256 id_) external virtual returns (uint256[] memory amountsOut);

    // Off-chain auction variant
    function settle(uint256 id_, Auction.Bid[] memory bids_) external virtual returns (uint256[] memory amountsOut);
}

// TODO abstract for now so compiler doesn't complain
abstract contract AuctionHouse is Derivatizer, Auctioneer, Router {
    using SafeTransferLib for ERC20;

    /// Implement the router functionality here since it combines all of the base functionality

    // ========== ERRORS ========== //
    error AmountLessThanMinimum();
    error InvalidHook();
    error UnsupportedToken(ERC20 token_);

    // ========== EVENTS ========== //
    event Purchase(uint256 id, address buyer, address referrer, uint256 amount, uint256 payout);

    // ========== CONSTRUCTOR ========== //
    constructor(address protocol_) Router(protocol_) {}

    // ========== DIRECT EXECUTION ========== //

    function purchase(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_) external override returns (uint256 payout) {
        AuctionModule module = _getModuleForId(id_);

        // TODO should this not check if the auction is atomic?
        // Response: No, my thought was that the module will just revert on `purchase` if it's not atomic. Vice versa 

        // Calculate fees for purchase
        // 1. Calculate referrer fee
        // 2. Calculate protocol fee as the total expected fee amount minus the referrer fee
        //    to avoid issues with rounding from separate fee calculations
        // TODO think about how to reduce storage loads
        uint256 toReferrer = referrer_ == address(0) ? 0 : (amount_ * referrerFees[referrer_]) / FEE_DECIMALS;
        uint256 toProtocol = ((amount_ * (protocolFee + referrerFees[referrer_])) / FEE_DECIMALS) -
            toReferrer;

        // Load routing data for the lot
        Routing memory routing = lotRouting[id_];

        // Send purchase to auction house and get payout plus any extra output
        bytes memory auctionOutput;
        (payout, auctionOutput) = module.purchase(id_, amount_ - toReferrer - toProtocol, auctionData_);

        // Check that payout is at least minimum amount out
        // @dev Moved the slippage check from the auction to the AuctionHouse to allow different routing and purchase logic
        if (payout < minAmountOut_) revert AmountLessThanMinimum();

        // Update fee balances if non-zero
        if (toReferrer > 0) rewards[referrer_][routing.quoteToken] += toReferrer;
        if (toProtocol > 0) rewards[_protocol][routing.quoteToken] += toProtocol;

        // Handle transfers from purchaser and seller
        _handleTransfers(id_, routing, amount_, payout, toReferrer + toProtocol, approval_);

        // Handle payout to user, including creation of derivative tokens
        _handlePayout(id_, routing, recipient_, payout, auctionOutput);

        // Emit event
        emit Purchase(id_, msg.sender, referrer_, amount_, payout);
    }


    // ============ DELEGATED EXECUTION ========== //


    // ============ INTERNAL EXECUTION FUNCTIONS ========== //

    /// @notice     Handles transfer of funds from user and market owner/callback
    function _handleTransfers(
        uint256 id_,
        Routing memory routing_,
        uint256 amount_,
        uint256 payout_,
        uint256 feePaid_,
        bytes calldata approval_
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
        if (routing_.quoteToken.balanceOf(address(this)) < quoteBalance + amount_)
            revert UnsupportedToken(routing_.quoteToken);

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
            if (routing_.baseToken.balanceOf(address(this)) < (baseBalance + payout_))
                revert InvalidHook();
        } else {
            // If no callback is provided, transfer tokens from market owner to this contract
            // for payout.
            // Check balance before and after to ensure full amount received, revert if not
            // Handles edge cases like fee-on-transfer tokens (which are not supported)
            uint256 baseBalance = routing_.baseToken.balanceOf(address(this));
            routing_.baseToken.safeTransferFrom(routing_.owner, address(this), payout_);
            if (routing_.baseToken.balanceOf(address(this)) < (baseBalance + payout_))
                revert UnsupportedToken(routing_.baseToken);

            routing_.quoteToken.safeTransfer(routing_.owner, amountLessFee);
        }
    }

    function _handlePayout(
        uint256 lotId_,
        Routing memory routing_,
        address recipient_,
        uint256 payout_,
        bytes memory auctionOutput_
    ) internal {
        // If no derivative, then the payout is sent directly to the recipient
        // Otherwise, send parameters and payout to the derivative to mint to recipient
        if (fromKeycode(routing_.derivativeType) == bytes5("")) {
            // No derivative, send payout to recipient
            routing_.baseToken.safeTransfer(recipient_, payout_);
        } else {
            // Get the module for the derivative type
            // We assume that the module type has been checked when the lot was created
            DerivativeModule module = _getSpecificDerivativeModule(routing_.derivativeType, routing_.derivativeVersion);

            bytes memory derivativeParams = routing_.derivativeParams;
            
            // TODO lookup condensor module from combination of auction and derivative types
            // If condenser specified, condense auction output and derivative params before sending to derivative module
            if (fromKeycode(routing_.condenserType) != bytes5("")) {
               // Get condenser module
                // CondenserModule condenser = CondenserModule(_getModuleIfInstalled(routing_.condenserType));

                // Condense auction output and derivative params
                // derivativeParams = condenser.condense(auctionOutput_, derivativeParams);
            }

            // Approve the module to transfer payout tokens
            routing_.baseToken.safeApprove(address(module), payout_);

            // Call the module to mint derivative tokens to the recipient
            module.mint(recipient_,derivativeParams, payout_, routing_.wrapDerivative);
        } 
    }
}