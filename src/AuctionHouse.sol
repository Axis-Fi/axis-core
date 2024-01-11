/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

import {Derivatizer} from "src/bases/Derivatizer.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";
import {CondenserModule} from "src/modules/Condenser.sol";

import {DerivativeModule} from "src/modules/Derivative.sol";

import {Auction, AuctionModule} from "src/modules/Auction.sol";

import {Veecode, fromVeecode, WithModules} from "src/modules/Modules.sol";

abstract contract FeeManager {
// TODO write fee logic in separate contract to keep it organized
// Router can inherit
}

abstract contract Router is FeeManager {
    // ========== DATA STRUCTURES ========== //
    struct Settlement {
        Auction.Bid[] winningBids;
        bytes[] bidSignatures;
        uint256[] amountsIn;
        uint256[] amountsOut;
        bytes validityProof;
        bytes[] approvals; // optional, permit 2 token approvals
        bytes[] allowlistProofs; // optional, allowlist proofs
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
    address internal immutable PROTOCOL;

    // ========== CONSTRUCTOR ========== //

    constructor(address protocol_) {
        PROTOCOL = protocol_;
    }

    // ========== ATOMIC AUCTIONS ========== //

    /// @param approval_ - (Optional) Permit approval signature for the quoteToken
    function purchase(
        address recipient_,
        address referrer_,
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_,
        bytes calldata auctionData_,
        bytes calldata approval_
    ) external virtual returns (uint256 payout);

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
        Settlement memory settlement_
    ) external virtual;
}

/// @title      AuctionHouse
/// @notice     As its name implies, the AuctionHouse is where auctions take place and the core of the protocol.
contract AuctionHouse is Derivatizer, Auctioneer, Router {
    using SafeTransferLib for ERC20;

    /// Implement the router functionality here since it combines all of the base functionality

    // ========== ERRORS ========== //
    error AmountLessThanMinimum();
    error InvalidHook();
    error InvalidBidder(address bidder_);
    error NotAuthorized();
    error UnsupportedToken(ERC20 token_);

    // ========== EVENTS ========== //
    event Purchase(uint256 id, address buyer, address referrer, uint256 amount, uint256 payout);

    // ========== CONSTRUCTOR ========== //
    constructor(address protocol_) Router(protocol_) WithModules(msg.sender) {}

    // ========== DIRECT EXECUTION ========== //

    // ========== AUCTION FUNCTIONS ========== //

    function allocateFees(
        address referrer_,
        ERC20 quoteToken_,
        uint256 amount_
    ) internal returns (uint256 totalFees) {
        // Calculate fees for purchase
        (uint256 toReferrer, uint256 toProtocol) = calculateFees(referrer_, amount_);

        // Update fee balances if non-zero
        if (toReferrer > 0) rewards[referrer_][quoteToken_] += toReferrer;
        if (toProtocol > 0) rewards[PROTOCOL][quoteToken_] += toProtocol;

        return toReferrer + toProtocol;
    }

    function calculateFees(address referrer_, uint256 amount_) internal view returns (uint256 toReferrer, uint256 toProtocol) {
        // TODO should protocol and/or referrer be able to charge different fees based on the type of auction being used?

        // Calculate fees for purchase
        // 1. Calculate referrer fee
        // 2. Calculate protocol fee as the total expected fee amount minus the referrer fee
        //    to avoid issues with rounding from separate fee calculations
        if (referrer_ == address(0)) {
            // There is no referrer
            toProtocol = (amount_ * protocolFee) / FEE_DECIMALS;
        } else {
            uint256 referrerFee = referrerFees[referrer_]; // reduce to single SLOAD
            if (referrerFee == 0) {
                // There is a referrer, but they have not set a fee
                toProtocol = (amount_ * protocolFee) / FEE_DECIMALS;
            } else {
                // There is a referrer and they have set a fee
                toReferrer = (amount_ * referrerFee) / FEE_DECIMALS;
                toProtocol = ((amount_ * (protocolFee + referrerFee)) / FEE_DECIMALS) - toReferrer;
            }
        }
    }

    function purchase(
        address recipient_,
        address referrer_,
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_,
        bytes calldata auctionData_,
        bytes calldata approval_
    ) external override returns (uint256 payout) {
        // TODO should this not check if the auction is atomic?
        // Response: No, my thought was that the module will just revert on `purchase` if it's not atomic. Vice versa

        // Load routing data for the lot
        Routing memory routing = lotRouting[id_];

        // Check that sender is on the allowlist, if there is one
        // TODO


        // Calculate fees for purchase
        uint256 totalFees = allocateFees(referrer_, routing.quoteToken, amount_);

        // Send purchase to auction house and get payout plus any extra output
        bytes memory auctionOutput;
        {
            AuctionModule module = _getModuleForId(id_);
            (payout, auctionOutput) = module.purchase(id_, amount_ - totalFees, auctionData_);
        }

        // Check that payout is at least minimum amount out
        // @dev Moved the slippage check from the auction to the AuctionHouse to allow different routing and purchase logic
        if (payout < minAmountOut_) revert AmountLessThanMinimum();

        // Handle transfers from purchaser and seller
        _handleTransfers(id_, routing, amount_, payout, totalFees, approval_);

        // Handle payout to user, including creation of derivative tokens
        _handlePayout(routing, recipient_, payout, auctionOutput);

        // Emit event
        emit Purchase(id_, msg.sender, referrer_, amount_, payout);
    }

    // TODO need a delegated execution function for purchase and bid because we check allowlist on the caller in the normal functions

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
    // Lots of parameters, likely need to consolidate
    function settle(
        uint256 id_,
        Settlement memory settlement_
    ) external override {
        // Load routing data for the lot
        Routing memory routing = lotRouting[id_];

        // Validate that sender is authorized to settle the auction
        // TODO

        // Validate array lengths all match
        uint256 len = settlement_.winningBids.length;
        if (len != settlement_.bidSignatures.length || len != settlement_.amountsIn.length || len != settlement_.amountsOut.length || len != settlement_.approvals.length || len != settlement_.allowlistProofs.length) revert InvalidParams();

        // Bid-level validation and fee calculations
        uint256[] memory amountsInLessFees = new uint256[](len);
        uint256 totalProtocolFee;
        uint256 totalAmountInLessFees;
        uint256 totalAmountOut;
        for (uint256 i; i < len; i++) {
            // If there is an allowlist, validate that the winners are on the allowlist
            if (address(routing.allowlist) != address(0)) {
                if (!routing.allowlist.isAllowed(settlement_.winningBids[i].bidder, settlement_.allowlistProofs[i])) revert InvalidBidder(settlement_.winningBids[i].bidder);
            }

            // Check that the amounts out are at least the minimum specified by the bidder
            // If a bid is a partial fill, then it's amountIn will be less than the amount specified by the bidder
            // If so, we need to adjust the minAmountOut proportionally for the slippage check
            // We also verify that the amountIn is not more than the bidder specified
            uint256 minAmountOut = settlement_.winningBids[i].minAmountOut;
            if (settlement_.amountsIn[i] > settlement_.winningBids[i].amount) {
                revert InvalidParams();
            } else if (settlement_.amountsIn[i] < settlement_.winningBids[i].amount) {
                minAmountOut = (minAmountOut * settlement_.amountsIn[i]) / settlement_.winningBids[i].amount; // TODO need to think about scaling and rounding here
            }
            if (settlement_.amountsOut[i] < minAmountOut) revert AmountLessThanMinimum();

            // Calculate fees from bid amount
            (uint256 toReferrer, uint256 toProtocol) = calculateFees(settlement_.winningBids[i].referrer, settlement_.amountsIn[i]);
            amountsInLessFees[i] = settlement_.amountsIn[i] - toReferrer - toProtocol;

            // Update referrer fee balances if non-zero and increment the total protocol fee
            if (toReferrer > 0) rewards[settlement_.winningBids[i].referrer][routing.quoteToken] += toReferrer;
            totalProtocolFee += toProtocol;

            // Increment total amount out
            totalAmountInLessFees += amountsInLessFees[i];
            totalAmountOut += settlement_.amountsOut[i];
        }

        // Update protocol fee if not zero
        if (totalProtocolFee > 0) rewards[PROTOCOL][routing.quoteToken] += totalProtocolFee;

        // Send auction inputs to auction module to validate settlement
        // We do this because the format of the bids and signatures is specific to the auction module
        // Some common things to check:
        // 1. Total of amounts out is not greater than capacity
        // 2. Minimum price is enforced
        // 3. Minimum bid size is enforced
        // 4. Minimum capacity sold is enforced
        AuctionModule module = _getModuleForId(id_);

        // TODO update auction module interface and base function to handle these inputs, and perhaps others
        bytes memory auctionOutput = module.settle(id_, settlement_.winningBids, settlement_.bidSignatures, amountsInLessFees, settlement_.amountsOut, settlement_.validityProof);
        
        // Iterate through bids, handling transfers and payouts
        // Have to transfer to auction house first since fee is in quote token
        // Check balance before and after to ensure full amount received, revert if not
        // Handles edge cases like fee-on-transfer tokens (which are not supported)
        for (uint256 i; i < len; i++) {
            // TODO use permit2 approvals if provided

            uint256 quoteBalance = routing.quoteToken.balanceOf(address(this));
            routing.quoteToken.safeTransferFrom(msg.sender, address(this), settlement_.amountsIn[i]);
            if (routing.quoteToken.balanceOf(address(this)) < quoteBalance + settlement_.amountsIn[i]) {
                revert UnsupportedToken(routing.quoteToken);
            }
        }

        // If hooks address supplied, transfer tokens from auction house to hooks contract, 
        // then execute the hook function, and ensure proper amount of tokens transferred in.
        if (address(routing.hooks) != address(0)) {
            // Send quote token to callback (transferred in first to allow use during callback)
            routing.quoteToken.safeTransfer(address(routing.hooks), totalAmountInLessFees);

            // Call the callback function to receive payout tokens for payout
            uint256 baseBalance = routing.baseToken.balanceOf(address(this));
            routing.hooks.mid(id_, totalAmountInLessFees, totalAmountOut);

            // Check to ensure that the callback sent the requested amount of payout tokens back to the teller
            if (routing.baseToken.balanceOf(address(this)) < (baseBalance + totalAmountOut)) {
                revert InvalidHook();
            }
        } else {
            // If no hook is provided, transfer tokens from auction owner to this contract
            // for payout.
            // Check balance before and after to ensure full amount received, revert if not
            // Handles edge cases like fee-on-transfer tokens (which are not supported)
            uint256 baseBalance = routing.baseToken.balanceOf(address(this));
            routing.baseToken.safeTransferFrom(routing.owner, address(this), totalAmountOut);
            if (routing.baseToken.balanceOf(address(this)) < (baseBalance + totalAmountOut)) {
                revert UnsupportedToken(routing.baseToken);
            }

            routing.quoteToken.safeTransfer(routing.owner, totalAmountInLessFees);
        }

        // Handle payouts to bidders
        for (uint256 i; i < len; i++) {
            // Handle payout to user, including creation of derivative tokens
            _handlePayout(routing, settlement_.winningBids[i].bidder, settlement_.amountsOut[i], auctionOutput);
        }
    }

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
        if (routing_.quoteToken.balanceOf(address(this)) < quoteBalance + amount_) {
            revert UnsupportedToken(routing_.quoteToken);
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
                revert UnsupportedToken(routing_.baseToken);
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
