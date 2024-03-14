// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {FixedPointMathLib as Math} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {Auctioneer} from "src/bases/Auctioneer.sol";
import {FeeManager} from "src/bases/FeeManager.sol";

import {DerivativeModule} from "src/modules/Derivative.sol";
import {Auction, AuctionModule} from "src/modules/Auction.sol";

import {
    Veecode, fromVeecode, Keycode, keycodeFromVeecode, WithModules
} from "src/modules/Modules.sol";

import {ICallback} from "src/interfaces/ICallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @title      Router
/// @notice     An interface to define the AuctionHouse's buyer-facing functions
abstract contract Router {
    // ========== DATA STRUCTURES ========== //

    /// @notice     Parameters used by the purchase function
    /// @dev        This reduces the number of variables in scope for the purchase function
    ///
    /// @param      recipient           Address to receive payout
    /// @param      referrer            Address of referrer
    /// @param      lotId               Lot ID
    /// @param      amount              Amount of quoteToken to purchase with (in native decimals)
    /// @param      minAmountOut        Minimum amount of baseToken to receive
    /// @param      auctionData         Custom data used by the auction module
    /// @param      permit2Data_        Permit2 approval for the quoteToken
    struct PurchaseParams {
        address recipient;
        address referrer;
        uint96 lotId;
        uint96 amount;
        uint96 minAmountOut;
        bytes auctionData;
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
    /// @param      permit2Data_        Permit2 approval for the quoteToken (abi-encoded Permit2Approval struct)
    struct BidParams {
        uint96 lotId;
        address referrer;
        uint96 amount;
        bytes auctionData;
        bytes permit2Data;
    }

    // ========== ATOMIC AUCTIONS ========== //

    /// @notice     Purchase a lot from an atomic auction
    /// @notice     Permit2 is utilised to simplify token transfers
    ///
    /// @param      params_         Purchase parameters
    /// @param      callbackData_   Custom data provided to the onPurchase callback
    /// @return     payout          Amount of baseToken received by `recipient_` (in native decimals)
    function purchase(
        PurchaseParams memory params_,
        bytes calldata callbackData_
    ) external virtual returns (uint96 payout);

    // ========== BATCH AUCTIONS ========== //

    /// @notice     Bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Store the bid
    ///             3. Transfer the amount of quote token from the bidder
    ///
    /// @param      params_         Bid parameters
    /// @param      callbackData_   Custom data provided to the onBid callback
    /// @return     bidId           Bid ID
    function bid(
        BidParams memory params_,
        bytes calldata callbackData_
    ) external virtual returns (uint64 bidId);

    /// @notice     Refund a bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Pass the request to the auction module to validate and update data
    ///             3. Send the refund to the bidder
    ///
    /// @param      lotId_          Lot ID
    /// @param      bidId_          Bid ID
    function refundBid(uint96 lotId_, uint64 bidId_) external virtual;

    /// @notice     Claim bid payouts and/or refunds after a batch auction has settled
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the lot ID
    ///             2. Pass the request to the auction module to validate and update bid data
    ///             3. Send the refund and/or payout to the bidders
    ///
    /// @param      lotId_          Lot ID
    /// @param      bidIds_         Bid IDs
    function claimBids(uint96 lotId_, uint64[] calldata bidIds_) external virtual;

    /// @notice     Settle a batch auction
    /// @notice     This function is used for versions with on-chain storage of bids and settlement
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the lot
    ///             2. Pass the request to the auction module to calculate winning bids
    ///             3. Collect the payout from the seller (if not pre-funded)
    ///             4. If there is a partial fill, sends the refund and payout to the bidder
    ///             5. Send the fees to the curator
    ///
    /// @param      lotId_          Lot ID
    function settle(uint96 lotId_) external virtual;

    /// @notice     Claim the proceeds of a settled auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the lot
    ///             2. Pass the request to the auction module to get the proceeds data
    ///             3. Send the proceeds (quote tokens) to the seller
    ///             4. Refund any unused base tokens to the seller
    ///
    /// @param      lotId_          Lot ID
    /// @param      callbackData_   Custom data provided to the onClaimProceeds callback
    function claimProceeds(uint96 lotId_, bytes calldata callbackData_) external virtual;
}

/// @title      AuctionHouse
/// @notice     As its name implies, the AuctionHouse is where auctions are created, bid on, and settled. The core protocol logic is implemented here.
contract AuctionHouse is Auctioneer, Router, FeeManager {
    using Callbacks for ICallback;

    // ========== ERRORS ========== //

    error AmountLessThanMinimum();
    error InsufficientFunding();

    // ========== EVENTS ========== //

    event Purchase(
        uint96 indexed lotId,
        address indexed buyer,
        address referrer,
        uint256 amount,
        uint256 payout
    );

    event Bid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder, uint256 amount);

    event RefundBid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder);

    // TODO events for ClaimBid, ClaimProceeds?

    event Settle(uint96 indexed lotId);

    // ========== STATE VARIABLES ========== //

    address internal immutable _PERMIT2;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address protocol_,
        address permit2_
    ) FeeManager(protocol_) WithModules(owner_) {
        _PERMIT2 = permit2_;
    }

    // ========== ATOMIC AUCTIONS ========== //

    /// @inheritdoc Router
    /// @dev        This fuction handles the following:
    ///             1. Calculates the fees for the purchase
    ///             2. Sends the purchase amount to the auction module
    ///             3. Records the purchase on the auction module
    ///             4. Transfers the quote token from the caller
    ///             5. Transfers the quote token to the seller
    ///             5. Transfers the base token from the seller or executes the callback
    ///             6. Transfers the base token to the recipient
    ///
    ///             Note that this function will deduct from the payment amount to cover the protocol and referrer fees. The fees at the time of purchase are used.
    ///
    ///             This function reverts if:
    ///             - `lotId_` is invalid
    ///             - The respective auction module reverts
    ///             - `payout` is less than `minAmountOut_`
    ///             - The caller does not have sufficient balance of the quote token
    ///             - The seller does not have sufficient balance of the payout token
    ///             - Any of the callbacks fail
    ///             - Any of the token transfers fail
    ///             - re-entrancy is detected
    function purchase(
        PurchaseParams memory params_,
        bytes calldata callbackData_
    ) external override nonReentrant returns (uint96 payoutAmount) {
        _isLotValid(params_.lotId);

        // Load routing data for the lot
        Routing storage routing = lotRouting[params_.lotId];

        // Calculate quote fees for purchase
        // Note: this enables protocol and referrer fees to be changed between purchases
        uint96 amountLessFees;
        {
            Keycode auctionKeycode = keycodeFromVeecode(routing.auctionReference);
            uint96 totalFees = _allocateQuoteFees(
                fees[auctionKeycode].protocol,
                fees[auctionKeycode].referrer,
                params_.referrer,
                routing.seller,
                routing.quoteToken,
                params_.amount
            );
            unchecked {
                amountLessFees = params_.amount - totalFees;
            }
        }

        // Send purchase to auction house and get payout plus any extra output
        bytes memory auctionOutput;
        (payoutAmount, auctionOutput) = _getModuleForId(params_.lotId).purchase(
            params_.lotId, amountLessFees, params_.auctionData
        );

        // Check that payout is at least minimum amount out
        // @dev Moved the slippage check from the auction to the AuctionHouse to allow different routing and purchase logic
        if (payoutAmount < params_.minAmountOut) revert AmountLessThanMinimum();

        // Collect payment from the purchaser
        _collectPayment(
            params_.amount, routing.quoteToken, Transfer.decodePermit2Approval(params_.permit2Data)
        );

        // Send payment, this function handles routing of the quote tokens correctly
        _sendPayment(routing.seller, amountLessFees, routing.quoteToken, routing.callbacks);

        // Calculate the curator fee (if applicable)
        uint96 curatorFeePayout = _calculatePayoutFees(
            lotFees[params_.lotId].curated, lotFees[params_.lotId].curatorFee, payoutAmount
        );

        // If not prefunded, collect payout from auction owner or callbacks contract, if not prefunded
        // If prefunded, call the onPurchase callback
        if (routing.funding == 0) {
            // If callbacks contract is configured to send base tokens, then source the payout from the callbacks contract
            if (Callbacks.hasPermission(routing.callbacks, Callbacks.SEND_BASE_TOKENS_FLAG)) {
                uint256 balanceBefore = routing.baseToken.balanceOf(address(this));

                // The onPurchase callback is expected to transfer the base tokens
                Callbacks.onPurchase(
                    routing.callbacks,
                    params_.lotId,
                    msg.sender,
                    amountLessFees,
                    payoutAmount + curatorFeePayout,
                    false,
                    callbackData_
                );

                // Check that the mid hook transferred the expected amount of payout tokens
                if (
                    routing.baseToken.balanceOf(address(this))
                        < balanceBefore + payoutAmount + curatorFeePayout
                ) {
                    revert InvalidCallback();
                }
            }
            // Otherwise, transfer directly from the auction owner
            // Still call the onPurchase callback to allow for custom logic
            else {
                Transfer.transferFrom(
                    routing.baseToken,
                    routing.seller,
                    address(this),
                    payoutAmount + curatorFeePayout,
                    true
                );

                // Call the onPurchase callback
                Callbacks.onPurchase(
                    routing.callbacks,
                    params_.lotId,
                    msg.sender,
                    amountLessFees,
                    payoutAmount + curatorFeePayout,
                    true,
                    callbackData_
                );
            }
        } else {
            // If the auction is prefunded, call the onPurchase callback
            Callbacks.onPurchase(
                routing.callbacks,
                params_.lotId,
                msg.sender,
                amountLessFees,
                payoutAmount + curatorFeePayout,
                true,
                callbackData_
            );

            // Decrease the funding amount (if applicable)
            // Check invariant
            if (routing.funding < payoutAmount + curatorFeePayout) revert InsufficientFunding();
            unchecked {
                routing.funding -= payoutAmount + curatorFeePayout;
            }
        }

        // Send payout to recipient
        _sendPayout(params_.recipient, payoutAmount, routing, auctionOutput);

        // Send curator fee to curator
        if (curatorFeePayout > 0) {
            _sendPayout(lotFees[params_.lotId].curator, curatorFeePayout, routing, auctionOutput);
        }

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
    ///             - re-entrancy is detected
    function bid(
        BidParams memory params_,
        bytes calldata callbackData_
    ) external override nonReentrant returns (uint64 bidId) {
        _isLotValid(params_.lotId);

        // Record the bid on the auction module
        // The module will determine if the bid is valid - minimum bid size, minimum price, auction status, etc
        bidId = _getModuleForId(params_.lotId).bid(
            params_.lotId, msg.sender, params_.referrer, params_.amount, params_.auctionData
        );

        // Transfer the quote token from the bidder
        _collectPayment(
            params_.amount,
            lotRouting[params_.lotId].quoteToken,
            Transfer.decodePermit2Approval(params_.permit2Data)
        );

        // Call the onBid callback
        Callbacks.onBid(
            lotRouting[params_.lotId].callbacks,
            params_.lotId,
            bidId,
            msg.sender,
            params_.amount,
            callbackData_
        );

        // Emit event
        emit Bid(params_.lotId, bidId, msg.sender, params_.amount);

        return bidId;
    }

    /// @inheritdoc Router
    /// @dev        This function reverts if:
    ///             - the lot ID is invalid
    ///             - the auction module reverts when cancelling the bid
    ///             - re-entrancy is detected
    function refundBid(uint96 lotId_, uint64 bidId_) external override nonReentrant {
        _isLotValid(lotId_);

        // Transfer the quote token to the bidder
        // The ownership of the bid has already been verified by the auction module
        Transfer.transfer(
            lotRouting[lotId_].quoteToken,
            msg.sender,
            // Refund the bid on the auction module
            // The auction module is responsible for validating the bid and authorizing the caller
            _getModuleForId(lotId_).refundBid(lotId_, bidId_, msg.sender),
            false
        );

        // Emit event
        emit RefundBid(lotId_, bidId_, msg.sender);
    }

    /// @inheritdoc Router
    /// @dev        This function reverts if:
    ///             - the lot ID is invalid
    ///             - the auction module reverts when claiming the bids
    ///             - re-entrancy is detected
    function claimBids(uint96 lotId_, uint64[] calldata bidIds_) external override nonReentrant {
        _isLotValid(lotId_);

        // Claim the bids on the auction module
        // The auction module is responsible for validating the bid and authorizing the caller
        (Auction.BidClaim[] memory bidClaims, bytes memory auctionOutput) =
            _getModuleForId(lotId_).claimBids(lotId_, bidIds_);

        // Load routing data for the lot
        Routing storage routing = lotRouting[lotId_];

        // Load fee data
        uint48 protocolFee = lotFees[lotId_].protocolFee;
        uint48 referrerFee = lotFees[lotId_].referrerFee;

        // Iterate through the bid claims and handle each one
        uint256 bidClaimsLen = bidClaims.length;
        for (uint256 i = 0; i < bidClaimsLen; i++) {
            Auction.BidClaim memory bidClaim = bidClaims[i];

            // If payout is greater than zero, then the bid was filled.
            // Otherwise, it was not and the bidder is refunded the paid amount.
            if (bidClaim.payout > 0) {
                // Allocate quote and protocol fees for bid
                _allocateQuoteFees(
                    protocolFee,
                    referrerFee,
                    bidClaim.referrer,
                    routing.seller,
                    routing.quoteToken,
                    bidClaim.paid
                );

                // Reduce funding by the payout amount
                unchecked {
                    routing.funding -= bidClaim.payout;
                }

                // Send the payout to the bidder
                _sendPayout(bidClaim.bidder, bidClaim.payout, routing, auctionOutput);
            } else {
                // Refund the paid amount to the bidder
                Transfer.transfer(routing.quoteToken, bidClaim.bidder, bidClaim.paid, false);
            }
        }
    }

    /// @inheritdoc Router
    /// @dev        This function handles the following:
    ///             - Settles the auction on the auction module
    ///             - Calculates the payout amount, taking partial fill into consideration
    ///             - Caches the fees for the lot
    ///             - Calculates the fees taken on the quote token
    ///             - Collects the payout from the seller (if necessary)
    ///             - Sends the refund and payout to the bidder (if there is a partial fill)
    ///             - Sends the payout to the curator (if curation is approved)
    ///
    ///             This function reverts if:
    ///             - the lot ID is invalid
    ///             - the auction module reverts when settling the auction
    ///             - collecting the payout from the seller fails
    ///             - re-entrancy is detected
    function settle(uint96 lotId_) external override nonReentrant {
        // Validation
        _isLotValid(lotId_);

        // Settle the lot on the auction module and get the winning bids
        // Reverts if the auction cannot be settled yet
        AuctionModule module = _getModuleForId(lotId_);

        // Store the capacity before settling
        uint96 capacity = module.remainingCapacity(lotId_);

        // Settle the auction
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = module.settle(lotId_);

        // Check if the auction settled
        // If so, calculate fees, handle partial bid, transfer proceeds + (possible) refund to seller, and curator fee
        if (settlement.totalIn > 0 && settlement.totalOut > 0) {
            // Load curator data and calculate fee (excluding any refunds of capacity)
            FeeData storage feeData = lotFees[lotId_];

            // Load routing data for the lot
            Routing storage routing = lotRouting[lotId_];

            // Store the protocol and referrer fees
            // If this is not done, the amount that the seller receives could be modified after settlement
            {
                Keycode auctionKeycode = keycodeFromVeecode(routing.auctionReference);
                feeData.protocolFee = fees[auctionKeycode].protocol;
                feeData.referrerFee = fees[auctionKeycode].referrer;
            }

            uint96 curatorFeePayout =
                _calculatePayoutFees(feeData.curated, feeData.curatorFee, capacity);

            // settle() is for batch auctions only, and all batch auctions are prefunded.
            // Payout has already been collected at the time of auction creation and curation

            // Check if there was a partial fill and handle the payout + refund
            if (settlement.pfBidder != address(0)) {
                // Allocate quote and protocol fees for bid
                _allocateQuoteFees(
                    feeData.protocolFee,
                    feeData.referrerFee,
                    settlement.pfReferrer,
                    routing.seller,
                    routing.quoteToken,
                    // Reconstruct bid amount from the settlement price and the amount out
                    uint96(
                        Math.mulDivDown(
                            settlement.pfPayout, settlement.totalIn, settlement.totalOut
                        )
                    )
                );

                // Reduce funding by the payout amount
                unchecked {
                    routing.funding -= uint96(settlement.pfPayout);
                }

                // Send refund and payout to the bidder
                Transfer.transfer(
                    routing.quoteToken, settlement.pfBidder, settlement.pfRefund, false
                );
                _sendPayout(settlement.pfBidder, settlement.pfPayout, routing, auctionOutput);
            }

            // If the lot is under capacity, adjust the curator payout
            if (settlement.totalOut < capacity && curatorFeePayout > 0) {
                uint96 capacityRefund;
                unchecked {
                    capacityRefund = capacity - settlement.totalOut;
                }

                uint96 feeRefund =
                    uint96(Math.mulDivDown(curatorFeePayout, capacityRefund, capacity));
                // Can't be more than curatorFeePayout
                unchecked {
                    curatorFeePayout -= feeRefund;
                }
            }

            // Reduce funding by curator fee and send, if applicable
            if (curatorFeePayout > 0) {
                unchecked {
                    routing.funding -= curatorFeePayout;
                }
                _sendPayout(feeData.curator, curatorFeePayout, routing, auctionOutput);
            }
        }

        // Emit event
        emit Settle(lotId_);
    }

    /// @inheritdoc Router
    /// @dev        This function handles the following:
    ///             1. Validates the lot
    ///             2. Sends the proceeds to the seller
    ///             3. If the auction lot is pre-funded, any unused capacity and curator fees are refunded to the seller
    ///             4. Calls the onClaimProceeds callback on the hooks contract (if provided)
    ///
    ///             This function reverts if:
    ///             - the lot ID is invalid
    ///             - the lot is not settled
    ///             - the proceeds have already been claimed
    function claimProceeds(
        uint96 lotId_,
        bytes calldata callbackData_
    ) external override nonReentrant {
        // Validation
        _isLotValid(lotId_);

        // Call auction module to validate and update data
        (uint96 purchased_, uint96 sold_, uint96 payoutSent_) =
            _getModuleForId(lotId_).claimProceeds(lotId_);

        // Load data for the lot
        Routing storage routing = lotRouting[lotId_];

        // Calculate the referrer and protocol fees for the amount in
        // Fees are not allocated until the user claims their payout so that we don't have to iterate through them here
        // If a referrer is not set, that portion of the fee defaults to the protocol
        uint96 totalInLessFees;
        {
            (, uint96 toProtocol) = calculateQuoteFees(
                lotFees[lotId_].protocolFee, lotFees[lotId_].referrerFee, false, purchased_
            );
            unchecked {
                totalInLessFees = purchased_ - toProtocol;
            }
        }

        // Send payment in bulk to the address dictated by the callbacks address
        // If the callbacks contract is configured to receive quote tokens, send the quote tokens to the callbacks contract and call the onClaimProceeds callback
        // If not, send the quote tokens to the seller and call the onClaimProceeds callback
        _sendPayment(routing.seller, totalInLessFees, routing.quoteToken, routing.callbacks);

        // Refund any unused capacity and curator fees to the address dictated by the callbacks address
        // By this stage, a partial payout (if applicable) and curator fees have been paid, leaving only the payout amount (`totalOut`) remaining.
        uint96 prefundingRefund = routing.funding + payoutSent_ - sold_;
        unchecked {
            routing.funding -= prefundingRefund;
        }
        Transfer.transfer(
            routing.baseToken,
            _getAddressGivenCallbackBaseTokenFlag(routing.callbacks, routing.seller),
            prefundingRefund,
            false
        );

        // Call the onClaimProceeds callback
        Callbacks.onClaimProceeds(
            routing.callbacks, lotId_, totalInLessFees, prefundingRefund, callbackData_
        );
    }

    // ========== CURATION ========== //

    /// @notice     Accept curation request for a lot.
    /// @notice     If the curator wishes to charge a fee, it must be set before this function is called.
    /// @notice     Access controlled. Must be proposed curator for lot.
    /// @dev        This function reverts if:
    ///             - the lot ID is invalid
    ///             - the caller is not the proposed curator
    ///             - the auction has ended or been cancelled
    ///             - the auction is prefunded and the fee cannot be collected
    ///             - re-entrancy is detected
    ///
    /// @param     lotId_       Lot ID
    function curate(uint96 lotId_, bytes calldata callbackData_) external nonReentrant {
        _isLotValid(lotId_);

        FeeData storage feeData = lotFees[lotId_];

        // Check that the caller is the proposed curator
        if (msg.sender != feeData.curator) revert NotPermitted(msg.sender);

        AuctionModule module = _getModuleForId(lotId_);

        // Check that the curator has not already approved the auction
        // Check that the auction has not ended or been cancelled
        if (feeData.curated || module.hasEnded(lotId_) == true) revert InvalidState();

        Routing storage routing = lotRouting[lotId_];

        // Set the curator as approved
        feeData.curated = true;
        feeData.curatorFee = fees[keycodeFromVeecode(routing.auctionReference)].curator[msg.sender];

        // Calculate the fee amount based on the remaining capacity (must be in base token if auction is pre-funded)
        uint96 curatorFeePayout = uint96(
            _calculatePayoutFees(
                feeData.curated, feeData.curatorFee, module.remainingCapacity(lotId_)
            )
        );

        // If the auction is pre-funded (required for batch auctions), transfer the fee amount from the seller
        if (routing.funding > 0) {
            // Increment the funding
            // Cannot overflow, as capacity is bounded by uint96 and the curator fee has a maximum percentage
            unchecked {
                routing.funding += curatorFeePayout;
            }

            // If the callbacks contract is configured to send base tokens, then source the fee from the callbacks contract
            // Otherwise, transfer from the auction owner
            if (Callbacks.hasPermission(routing.callbacks, Callbacks.SEND_BASE_TOKENS_FLAG)) {
                uint256 balanceBefore = routing.baseToken.balanceOf(address(this));

                // The onCurate callback is expected to transfer the base tokens
                Callbacks.onCurate(routing.callbacks, lotId_, curatorFeePayout, true, callbackData_);

                // Check that the callback transferred the expected amount of base tokens
                if (routing.baseToken.balanceOf(address(this)) < balanceBefore + curatorFeePayout) {
                    revert InvalidCallback();
                }
            } else {
                // Don't need to check for fee on transfer here because it was checked on auction creation
                Transfer.transferFrom(
                    routing.baseToken, routing.seller, address(this), curatorFeePayout, false
                );

                // Call the onCurate callback
                Callbacks.onCurate(
                    routing.callbacks, lotId_, curatorFeePayout, false, callbackData_
                );
            }
        } else {
            // If the auction is not pre-funded, call the onCurate callback
            Callbacks.onCurate(routing.callbacks, lotId_, curatorFeePayout, false, callbackData_);
        }

        // Emit event that the lot is curated by the proposed curator
        emit Curated(lotId_, msg.sender);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc FeeManager
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

    /// @inheritdoc FeeManager
    function setProtocol(address protocol_) external override onlyOwner {
        _protocol = protocol_;
    }

    // ========== TOKEN TRANSFERS ========== //

    /// @notice     Collects payment of the quote token from the user
    /// @dev        This function handles the following:
    ///             1. Transfers the quote token from the user
    ///             1a. Uses Permit2 to transfer if approval signature is provided
    ///             1b. Otherwise uses a standard ERC20 transfer
    ///
    ///             This function reverts if:
    ///             - The Permit2 approval is invalid
    ///             - The caller does not have sufficient balance of the quote token
    ///             - Approval has not been granted to transfer the quote token
    ///             - The quote token transfer fails
    ///             - Transferring the quote token would result in a lesser amount being received
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

    /// @notice     Sends payment of the quote token to the seller
    /// @dev        This function handles the following:
    ///             1. Sends the payment amount to the seller or hook (if provided)
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
    /// @param      recipient_      Address to receive payout
    /// @param      payoutAmount_   Amount of payoutToken to send (in native decimals)
    /// @param      routingParams_  Routing parameters for the lot
    function _sendPayout(
        address recipient_,
        uint256 payoutAmount_,
        Routing memory routingParams_,
        bytes memory
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

            // Approve the module to transfer payout tokens when minting
            Transfer.approve(baseToken, address(module), payoutAmount_);

            // Call the module to mint derivative tokens to the recipient
            module.mint(
                recipient_,
                address(baseToken),
                routingParams_.derivativeParams,
                payoutAmount_,
                routingParams_.wrapDerivative
            );
        }
    }

    // ========== FEE FUNCTIONS ========== //

    function _allocateQuoteFees(
        uint96 protocolFee_,
        uint96 referrerFee_,
        address referrer_,
        address seller_,
        ERC20 quoteToken_,
        uint96 amount_
    ) internal returns (uint96 totalFees) {
        // Calculate fees for purchase
        (uint96 toReferrer, uint96 toProtocol) = calculateQuoteFees(
            protocolFee_, referrerFee_, referrer_ != address(0) && referrer_ != seller_, amount_
        );

        // Update fee balances if non-zero
        if (toReferrer > 0) rewards[referrer_][quoteToken_] += uint256(toReferrer);
        if (toProtocol > 0) rewards[_protocol][quoteToken_] += uint256(toProtocol);

        return toReferrer + toProtocol;
    }
}
