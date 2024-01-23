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
import {IAllowlist} from "src/interfaces/IAllowlist.sol";

// TODO define purpose
abstract contract FeeManager {
// TODO write fee logic in separate contract to keep it organized
// Router can inherit

// TODO disbursing fees
}

// TODO define purpose
abstract contract Router is FeeManager {
    // ========== DATA STRUCTURES ========== //

    /// @notice     Parameters used for Permit2 approvals
    struct Permit2Approval {
        uint48 deadline;
        uint256 nonce;
        bytes signature;
    }

    /// @notice     Parameters used by the purchase function
    /// @dev        This reduces the number of variables in scope for the purchase function
    ///
    /// @param      recipient           Address to receive payout
    /// @param      referrer            Address of referrer
    /// @param      lotId               Lot ID
    /// @param      amount              Amount of quoteToken to purchase with (in native decimals)
    /// @param      minAmountOut        Minimum amount of baseToken to receive
    /// @param      auctionData         Custom data used by the auction module
    /// @param      allowlistProof      Proof of allowlist inclusion
    /// @param      permit2Data_        Permit2 approval for the quoteToken
    struct PurchaseParams {
        address recipient;
        address referrer;
        uint96 lotId;
        uint256 amount;
        uint256 minAmountOut;
        bytes auctionData;
        bytes allowlistProof;
        bytes permit2Data;
    }

    /// @notice     Parameters used by the bid function
    /// @dev        This reduces the number of variables in scope for the bid function
    ///
    /// @param      lotId               Lot ID
    /// @param      recipient           Address to receive payout
    /// @param      referrer            Address of referrer
    /// @param      amount              Amount of quoteToken to purchase with (in native decimals)
    /// @param      auctionData         Custom data used by the auction module
    /// @param      allowlistProof      Proof of allowlist inclusion
    /// @param      permit2Data_        Permit2 approval for the quoteToken (abi-encoded Permit2Approval struct)
    struct BidParams {
        uint96 lotId;
        address recipient;
        address referrer;
        uint256 amount;
        bytes auctionData;
        bytes allowlistProof;
        bytes permit2Data;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     Fee paid to a front end operator in basis points (3 decimals). Set by the referrer, must be less than or equal to 5% (5e3).
    /// @dev        There are some situations where the fees may round down to zero if quantity of baseToken
    ///             is < 1e5 wei (can happen with big price differences on small decimal tokens). This is purely
    ///             a theoretical edge case, as the bond amount would not be practical.
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

    /// @notice     Purchase a lot from an atomic auction
    /// @notice     Permit2 is utilised to simplify token transfers
    ///
    /// @param      params_         Purchase parameters
    /// @return     payout          Amount of baseToken received by `recipient_` (in native decimals)
    function purchase(PurchaseParams memory params_) external virtual returns (uint256 payout);

    // ========== BATCH AUCTIONS ========== //

    /// @notice     Bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Store the bid
    ///             3. Transfer the amount of quote token from the bidder
    ///
    /// @param      params_         Bid parameters
    /// @return     bidId           Bid ID
    function bid(BidParams memory params_) external virtual returns (uint256 bidId);

    /// @notice     Cancel a bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Call the auction module to cancel the bid
    ///
    /// @param      lotId_          Lot ID
    /// @param      bidId_          Bid ID
    function cancelBid(uint96 lotId_, uint256 bidId_) external virtual;

    /// @notice     Settle a batch auction with the provided bids
    /// @notice     This function is used for on-chain storage of bids and external settlement
    ///
    /// @dev        The implementing function must perform the following:
    ///             1. Validate that the caller is authorized to settle the auction
    ///             2. Calculate fees
    ///             3. Pass the bids to the auction module to validate the settlement
    ///             4. Send payment to the auction owner
    ///             5. Collect payout from the auction owner
    ///             6. Send payout to each bidder
    ///
    /// @param      lotId_           Lot ID
    /// @param      winningBids_     Winning bids
    /// @param      settlementProof_ Proof of settlement validity
    /// @param      settlementData_  Settlement data
    function settle(
        uint96 lotId_,
        Auction.Bid[] calldata winningBids_,
        bytes calldata settlementProof_,
        bytes calldata settlementData_
    ) external virtual;

    /// @notice     Claims a refund for a failed or cancelled bid
    /// @dev        The implementing function must perform the following:
    ///             1. Validate that the `lotId_` is valid
    ///             2. Pass the request to the auction module to validate and update data
    ///             3. Send the refund to the bidder
    ///
    /// @param      lotId_           Lot ID
    /// @param      bidId_           Bid ID
    function claimRefund(uint96 lotId_, uint256 bidId_) external virtual;

    // ========== FEE MANAGEMENT ========== //

    /// @notice     Sets the fee for the protocol
    function setProtocolFee(uint48 protocolFee_) external virtual;

    /// @notice     Sets the fee for a referrer
    function setReferrerFee(address referrer_, uint48 referrerFee_) external virtual;
}

/// @title      AuctionHouse
/// @notice     As its name implies, the AuctionHouse is where auctions take place and the core of the protocol.
contract AuctionHouse is Derivatizer, Auctioneer, Router {
    using SafeTransferLib for ERC20;

    /// Implement the router functionality here since it combines all of the base functionality

    // ========== ERRORS ========== //

    error AmountLessThanMinimum();

    error UnsupportedToken(address token_);

    error InvalidHook();

    error InvalidBidder(address bidder_);

    // ========== EVENTS ========== //

    event Purchase(uint256 id, address buyer, address referrer, uint256 amount, uint256 payout);

    // ========== STATE VARIABLES ========== //

    IPermit2 internal immutable _PERMIT2;

    // ========== CONSTRUCTOR ========== //

    constructor(address protocol_, address permit2_) Router(protocol_) WithModules(msg.sender) {
        _PERMIT2 = IPermit2(permit2_);
    }

    // ========== FEE FUNCTIONS ========== //

    function _allocateFees(
        address referrer_,
        ERC20 quoteToken_,
        uint256 amount_
    ) internal returns (uint256 totalFees) {
        // Calculate fees for purchase
        (uint256 toReferrer, uint256 toProtocol) = _calculateFees(referrer_, amount_);

        // Update fee balances if non-zero
        if (toReferrer > 0) rewards[referrer_][quoteToken_] += toReferrer;
        if (toProtocol > 0) rewards[_PROTOCOL][quoteToken_] += toProtocol;

        return toReferrer + toProtocol;
    }

    function _allocateFees(
        Auction.Bid[] memory bids_,
        ERC20 quoteToken_
    ) internal returns (uint256 totalAmountIn, uint256 totalFees) {
        // Calculate fees for purchase
        uint256 bidCount = bids_.length;
        for (uint256 i; i < bidCount; i++) {
            // Calculate fees from bid amount
            (uint256 toReferrer, uint256 toProtocol) =
                _calculateFees(bids_[i].referrer, bids_[i].amount);

            // Update referrer fee balances if non-zero and increment the total protocol fee
            if (toReferrer > 0) {
                rewards[bids_[i].referrer][quoteToken_] += toReferrer;
            }
            totalFees += toReferrer + toProtocol;

            // Increment total amount in
            totalAmountIn += bids_[i].amount;
        }

        // Update protocol fee if not zero
        if (totalFees > 0) rewards[_PROTOCOL][quoteToken_] += totalFees;
    }

    function _calculateFees(
        address referrer_,
        uint256 amount_
    ) internal view returns (uint256 toReferrer, uint256 toProtocol) {
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

    // ========== AUCTION FUNCTIONS ========== //

    /// @notice     Determines if `caller_` is allowed to purchase/bid on a lot.
    ///             If no allowlist is defined, this function will return true.
    ///
    /// @param      allowlist_       Allowlist contract
    /// @param      lotId_           Lot ID
    /// @param      caller_          Address of caller
    /// @param      allowlistProof_  Proof of allowlist inclusion
    /// @return     bool             True if caller is allowed to purchase/bid on the lot
    function _isAllowed(
        IAllowlist allowlist_,
        uint256 lotId_,
        address caller_,
        bytes memory allowlistProof_
    ) internal view returns (bool) {
        if (address(allowlist_) == address(0)) {
            return true;
        } else {
            return allowlist_.isAllowed(lotId_, caller_, allowlistProof_);
        }
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
        if (!_isAllowed(routing.allowlist, params_.lotId, msg.sender, params_.allowlistProof)) {
            revert InvalidBidder(msg.sender);
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
        {
            Permit2Approval memory permit2Approval = params_.permit2Data.length == 0
                ? Permit2Approval({nonce: 0, deadline: 0, signature: bytes("")})
                : abi.decode(params_.permit2Data, (Permit2Approval));
            _collectPayment(
                params_.lotId, params_.amount, routing.quoteToken, routing.hooks, permit2Approval
            );
        }

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

    /// @inheritdoc Router
    /// @dev        This function reverts if:
    ///             - lotId is invalid
    ///             - the bidder is not on the optional allowlist
    ///             - the auction module reverts when creating a bid
    ///             - the quote token transfer fails
    function bid(BidParams memory params_)
        external
        override
        isValidLot(params_.lotId)
        returns (uint256)
    {
        // Load routing data for the lot
        Routing memory routing = lotRouting[params_.lotId];

        // Determine if the bidder is authorized to bid
        if (!_isAllowed(routing.allowlist, params_.lotId, msg.sender, params_.allowlistProof)) {
            revert InvalidBidder(msg.sender);
        }

        // Record the bid on the auction module
        // The module will determine if the bid is valid - minimum bid size, minimum price, auction status, etc
        uint256 bidId;
        {
            AuctionModule module = _getModuleForId(params_.lotId);
            bidId = module.bid(
                params_.lotId,
                msg.sender,
                params_.recipient,
                params_.referrer,
                params_.amount,
                params_.auctionData
            );
        }

        // Transfer the quote token from the bidder
        {
            Permit2Approval memory permit2Approval = params_.permit2Data.length == 0
                ? Permit2Approval({nonce: 0, deadline: 0, signature: bytes("")})
                : abi.decode(params_.permit2Data, (Permit2Approval));
            _collectPayment(
                params_.lotId, params_.amount, routing.quoteToken, routing.hooks, permit2Approval
            );
        }

        return bidId;
    }

    /// @inheritdoc Router
    function cancelBid(uint96 lotId_, uint256 bidId_) external override isValidLot(lotId_) {
        // Cancel the bid on the auction module
        AuctionModule module = _getModuleForId(lotId_);
        module.cancelBid(lotId_, bidId_, msg.sender);
    }

    /// @inheritdoc Router
    /// @dev        This function reverts if:
    ///             - the lot ID is invalid
    ///             - the caller is not authorized to settle the auction
    ///             - the auction module reverts when settling the auction
    ///             - transferring the quote token to the auction owner fails
    ///             - collecting the payout from the auction owner fails
    ///             - sending the payout to each bidder fails
    function settle(
        uint96 lotId_,
        Auction.Bid[] calldata winningBids_,
        bytes calldata settlementProof_,
        bytes calldata settlementData_
    ) external override isValidLot(lotId_) {
        // Load routing data for the lot
        Routing memory routing = lotRouting[lotId_];

        // Validate that sender is authorized to settle the auction
        // TODO

        // Send auction inputs to auction module to validate settlement
        // We do this because the format of the bids and signatures is specific to the auction module
        // Some common things to check:
        // 1. Total of amounts out is not greater than capacity
        // 2. Minimum price is enforced
        // 3. Minimum bid size is enforced
        // 4. Minimum capacity sold is enforced
        uint256[] memory amountsOut;
        bytes memory auctionOutput;
        {
            AuctionModule module = _getModuleForId(lotId_);
            (amountsOut, auctionOutput) =
                module.settle(lotId_, winningBids_, settlementProof_, settlementData_);
        }

        // Calculate fees
        uint256 totalAmountInLessFees;
        {
            (uint256 totalAmountIn, uint256 totalFees) =
                _allocateFees(winningBids_, routing.quoteToken);
            totalAmountInLessFees = totalAmountIn - totalFees;
        }

        // Assumes that payment has already been collected for each bid

        // Send payment in bulk to auction owner
        _sendPayment(routing.owner, totalAmountInLessFees, routing.quoteToken, routing.hooks);

        // Collect payout in bulk from the auction owner
        {
            // Calculate amount out
            uint256 totalAmountOut;
            {
                uint256 bidCount = amountsOut.length;
                for (uint256 i; i < bidCount; i++) {
                    // Increment total amount out
                    totalAmountOut += amountsOut[i];
                }
            }

            _collectPayout(lotId_, totalAmountInLessFees, totalAmountOut, routing);
        }

        // Handle payouts to bidders
        {
            uint256 bidCount = winningBids_.length;
            for (uint256 i; i < bidCount; i++) {
                // Send payout to each bidder
                _sendPayout(lotId_, winningBids_[i].bidder, amountsOut[i], routing, auctionOutput);
            }
        }
    }

    /// @inheritdoc Router
    function claimRefund(uint96 lotId_, uint256 bidId_) external override isValidLot(lotId_) {
        //
    }

    // // External submission and evaluation
    // function settle(uint256 id_, ExternalSettlement memory settlement_) external override {
    //     // Load routing data for the lot
    //     Routing memory routing = lotRouting[id_];

    //     // Validate that sender is authorized to settle the auction
    //     // TODO

    //     // Validate array lengths all match
    //     uint256 len = settlement_.bids.length;
    //     if (
    //         len != settlement_.bidSignatures.length || len != settlement_.amountsIn.length
    //             || len != settlement_.amountsOut.length || len != settlement_.approvals.length
    //             || len != settlement_.allowlistProofs.length
    //     ) revert InvalidParams();

    //     // Bid-level validation and fee calculations
    //     uint256[] memory amountsInLessFees = new uint256[](len);
    //     uint256 totalProtocolFee;
    //     uint256 totalAmountInLessFees;
    //     uint256 totalAmountOut;
    //     for (uint256 i; i < len; i++) {
    //         // If there is an allowlist, validate that the winners are on the allowlist
    //         if (
    //             !_isAllowed(
    //                 routing.allowlist,
    //                 id_,
    //                 settlement_.bids[i].bidder,
    //                 settlement_.allowlistProofs[i]
    //             )
    //         ) {
    //             revert InvalidBidder(settlement_.bids[i].bidder);
    //         }

    //         // Check that the amounts out are at least the minimum specified by the bidder
    //         // If a bid is a partial fill, then it's amountIn will be less than the amount specified by the bidder
    //         // If so, we need to adjust the minAmountOut proportionally for the slippage check
    //         // We also verify that the amountIn is not more than the bidder specified
    //         uint256 minAmountOut = settlement_.bids[i].minAmountOut;
    //         if (settlement_.amountsIn[i] > settlement_.bids[i].amount) {
    //             revert InvalidParams();
    //         } else if (settlement_.amountsIn[i] < settlement_.bids[i].amount) {
    //             minAmountOut =
    //                 (minAmountOut * settlement_.amountsIn[i]) / settlement_.bids[i].amount; // TODO need to think about scaling and rounding here
    //         }
    //         if (settlement_.amountsOut[i] < minAmountOut) revert AmountLessThanMinimum();

    //         // Calculate fees from bid amount
    //         (uint256 toReferrer, uint256 toProtocol) =
    //             _calculateFees(settlement_.bids[i].referrer, settlement_.amountsIn[i]);
    //         amountsInLessFees[i] = settlement_.amountsIn[i] - toReferrer - toProtocol;

    //         // Update referrer fee balances if non-zero and increment the total protocol fee
    //         if (toReferrer > 0) {
    //             rewards[settlement_.bids[i].referrer][routing.quoteToken] += toReferrer;
    //         }
    //         totalProtocolFee += toProtocol;

    //         // Increment total amount out
    //         totalAmountInLessFees += amountsInLessFees[i];
    //         totalAmountOut += settlement_.amountsOut[i];
    //     }

    //     // Update protocol fee if not zero
    //     if (totalProtocolFee > 0) rewards[_PROTOCOL][routing.quoteToken] += totalProtocolFee;

    //     // Send auction inputs to auction module to validate settlement
    //     // We do this because the format of the bids and signatures is specific to the auction module
    //     // Some common things to check:
    //     // 1. Total of amounts out is not greater than capacity
    //     // 2. Minimum price is enforced
    //     // 3. Minimum bid size is enforced
    //     // 4. Minimum capacity sold is enforced
    //     AuctionModule module = _getModuleForId(id_);

    //     // TODO update auction module interface and base function to handle these inputs, and perhaps others
    //     bytes memory auctionOutput = module.settle(
    //         id_,
    //         settlement_.bids,
    //         settlement_.bidSignatures,
    //         amountsInLessFees,
    //         settlement_.amountsOut,
    //         settlement_.validityProof
    //     );

    //     // Assumes that payment has already been collected for each bid

    //     // Send payment in bulk to auction owner
    //     _sendPayment(routing.owner, totalAmountInLessFees, routing.quoteToken, routing.hooks);

    //     // Collect payout in bulk from the auction owner
    //     _collectPayout(id_, totalAmountInLessFees, totalAmountOut, routing);

    //     // Handle payouts to bidders
    //     for (uint256 i; i < len; i++) {
    //         // Send payout to each bidder
    //         _sendPayout(
    //             id_, settlement_.bids[i].bidder, settlement_.amountsOut[i], routing, auctionOutput
    //         );
    //     }
    // }

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
    /// @param      permit2Approval_    Permit2 approval data (optional)
    function _collectPayment(
        uint256 lotId_,
        uint256 amount_,
        ERC20 quoteToken_,
        IHooks hooks_,
        Permit2Approval memory permit2Approval_
    ) internal {
        // Call pre hook on hooks contract if provided
        if (address(hooks_) != address(0)) {
            hooks_.pre(lotId_, amount_);
        }

        // If a Permit2 approval signature is provided, use it to transfer the quote token
        if (permit2Approval_.signature.length != 0) {
            _permit2Transfer(amount_, quoteToken_, permit2Approval_);
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
            // Transfer the payout token from the auction owner
            // `safeTransferFrom()` will revert upon failure or the lack of allowance or balance
            routingParams_.baseToken.safeTransferFrom(
                routingParams_.owner, address(this), payoutAmount_
            );

            // Check that it is not a fee-on-transfer token
            if (routingParams_.baseToken.balanceOf(address(this)) < balanceBefore + payoutAmount_) {
                revert UnsupportedToken(address(routingParams_.baseToken));
            }
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

            // Approve the module to transfer payout tokens when minting
            routingParams_.baseToken.safeApprove(address(module), payoutAmount_);

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
        uint256 balanceBefore = token_.balanceOf(address(this));

        // Transfer the quote token from the user
        // `safeTransferFrom()` will revert upon failure or the lack of allowance or balance
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
    /// @param      permit2Approval_      Permit2 approval data
    function _permit2Transfer(
        uint256 amount_,
        ERC20 token_,
        Permit2Approval memory permit2Approval_
    ) internal {
        uint256 balanceBefore = token_.balanceOf(address(this));

        // Use PERMIT2 to transfer the token from the user
        _PERMIT2.permitTransferFrom(
            IPermit2.PermitTransferFrom(
                IPermit2.TokenPermissions(address(token_), amount_),
                permit2Approval_.nonce,
                permit2Approval_.deadline
            ),
            IPermit2.SignatureTransferDetails({to: address(this), requestedAmount: amount_}),
            msg.sender, // Spender of the tokens
            permit2Approval_.signature
        );

        // Check that it is not a fee-on-transfer token
        if (token_.balanceOf(address(this)) < balanceBefore + amount_) {
            revert UnsupportedToken(address(token_));
        }
    }

    // ========== FEE MANAGEMENT ========== //

    /// @inheritdoc Router
    function setProtocolFee(uint48 protocolFee_) external override onlyOwner {
        protocolFee = protocolFee_;
    }

    /// @inheritdoc Router
    function setReferrerFee(address referrer_, uint48 referrerFee_) external override onlyOwner {
        referrerFees[referrer_] = referrerFee_;
    }
}
