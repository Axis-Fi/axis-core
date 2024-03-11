/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {FixedPointMathLib as Math} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {Auctioneer} from "src/bases/Auctioneer.sol";
import {FeeManager} from "src/bases/FeeManager.sol";

import {CondenserModule} from "src/modules/Condenser.sol";
import {DerivativeModule} from "src/modules/Derivative.sol";
import {Auction, AuctionModule} from "src/modules/Auction.sol";

import {
    Veecode, fromVeecode, Keycode, keycodeFromVeecode, WithModules
} from "src/modules/Modules.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";

/// @title      Router
/// @notice     An interface to define the routing of transactions to the appropriate auction module
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
    /// @param      allowlistProof      Proof of allowlist inclusion
    /// @param      permit2Data_        Permit2 approval for the quoteToken
    struct PurchaseParams {
        address recipient;
        address referrer;
        uint96 lotId;
        uint96 amount;
        uint96 minAmountOut;
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
        address referrer;
        uint96 amount;
        bytes auctionData;
        bytes allowlistProof;
        bytes permit2Data;
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
    function bid(BidParams memory params_) external virtual returns (uint64 bidId);

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
    function claimProceeds(uint96 lotId_) external virtual;
}

/// @title      AuctionHouse
/// @notice     As its name implies, the AuctionHouse is where auctions are created, bid on, and settled. The core protocol logic is implemented here.
contract AuctionHouse is Auctioneer, Router, FeeManager {
    // ========== ERRORS ========== //

    error AmountLessThanMinimum();

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
        uint96 lotId_,
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
    function purchase(PurchaseParams memory params_)
        external
        override
        nonReentrant
        returns (uint256 payoutAmount)
    {
        _isLotValid(params_.lotId);

        // Load routing data for the lot
        Routing storage routing = lotRouting[params_.lotId];

        // Check if the purchaser is on the allowlist
        if (!_isAllowed(routing.allowlist, params_.lotId, msg.sender, params_.allowlistProof)) {
            revert NotPermitted(msg.sender);
        }

        // Calculate quote fees for purchase
        // TODO this enables protocol and referrer fees to be changed between purchases
        uint256 amountLessFees;
        {
            Keycode auctionKeycode = keycodeFromVeecode(routing.auctionReference);
            amountLessFees = params_.amount
                - _allocateQuoteFees(
                    fees[auctionKeycode].protocol,
                    fees[auctionKeycode].referrer,
                    params_.referrer,
                    routing.seller,
                    routing.quoteToken,
                    params_.amount
                );
        }

        // Send purchase to auction house and get payout plus any extra output
        bytes memory auctionOutput;
        (payoutAmount, auctionOutput) = getModuleForId(params_.lotId).purchase(
            params_.lotId, uint96(amountLessFees), params_.auctionData
        );

        // Check that payout is at least minimum amount out
        // @dev Moved the slippage check from the auction to the AuctionHouse to allow different routing and purchase logic
        if (payoutAmount < params_.minAmountOut) revert AmountLessThanMinimum();

        // Collect payment from the purchaser
        _collectPayment(
            params_.lotId,
            params_.amount,
            routing.quoteToken,
            routing.hooks,
            Transfer.decodePermit2Approval(params_.permit2Data)
        );

        // Send payment to seller
        _sendPayment(routing.seller, amountLessFees, routing.quoteToken, routing.hooks);

        // Calculate the curator fee (if applicable)
        FeeData memory feeData = lotFees[params_.lotId];
        uint256 curatorFeePayout =
            _calculatePayoutFees(feeData.curated, feeData.curatorFee, payoutAmount);

        // Collect payout from seller, if needed
        if (routing.funding == 0) {
            // No need to update the funding amount, as it will be zero-ed out within this function
            _collectPayout(params_.lotId, amountLessFees, payoutAmount + curatorFeePayout, routing);
        }

        // Decrease the funding amount (if applicable)
        if (routing.funding > 0) {
            unchecked {
                routing.funding -= payoutAmount;
            }
        }

        // Send payout to recipient
        _sendPayout(params_.lotId, params_.recipient, payoutAmount, routing, auctionOutput);

        // Send curator fee to curator
        if (curatorFeePayout > 0) {
            // Decrease the funding amount
            if (routing.funding > 0) {
                unchecked {
                    routing.funding -= curatorFeePayout;
                }
            }

            _sendPayout(params_.lotId, feeData.curator, curatorFeePayout, routing, auctionOutput);
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
    function bid(BidParams memory params_) external override nonReentrant returns (uint64 bidId) {
        _isLotValid(params_.lotId);

        // Load routing data for the lot
        Routing memory routing = lotRouting[params_.lotId];

        // Determine if the bidder is authorized to bid
        if (!_isAllowed(routing.allowlist, params_.lotId, msg.sender, params_.allowlistProof)) {
            revert NotPermitted(msg.sender);
        }

        // Record the bid on the auction module
        // The module will determine if the bid is valid - minimum bid size, minimum price, auction status, etc
        bidId = getModuleForId(params_.lotId).bid(
            params_.lotId, msg.sender, params_.referrer, params_.amount, params_.auctionData
        );

        // Transfer the quote token from the bidder
        _collectPayment(
            params_.lotId,
            params_.amount,
            routing.quoteToken,
            routing.hooks,
            Transfer.decodePermit2Approval(params_.permit2Data)
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

        // Refund the bid on the auction module
        // The auction module is responsible for validating the bid and authorizing the caller
        uint256 refundAmount = getModuleForId(lotId_).refundBid(lotId_, bidId_, msg.sender);

        // Transfer the quote token to the bidder
        // The ownership of the bid has already been verified by the auction module
        Transfer.transfer(lotRouting[lotId_].quoteToken, msg.sender, refundAmount, false);

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
            getModuleForId(lotId_).claimBids(lotId_, bidIds_);

        // Load routing data for the lot
        Routing memory routing = lotRouting[lotId_];

        // Load fee data
        FeeData memory feeData = lotFees[lotId_];

        // Iterate through the bid claims and handle each one
        for (uint256 i = 0; i < bidClaims.length; i++) {
            Auction.BidClaim memory bidClaim = bidClaims[i];

            // If payout is greater than zero, then the bid was filled.
            // Otherwise, it was not and the bidder is refunded the paid amount.
            if (bidClaim.payout > 0) {
                // Allocate quote and protocol fees for bid
                _allocateQuoteFees(
                    feeData.protocolFee,
                    feeData.referrerFee,
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
                _sendPayout(lotId_, bidClaim.bidder, bidClaim.payout, routing, auctionOutput);
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
        // TODO this implementation is pretty opinionated about only having one partial fill.
        // The initial EMPAM works this way, but other batch auctions may not.
        // It may be better to allow arbitrary partial fills and handle them in the claimBid function instead of here.
        // However, this may change the desired behavior.

        // Validation
        _isLotValid(lotId_);

        // Settle the lot on the auction module and get the winning bids
        // Reverts if the auction cannot be settled yet
        AuctionModule module = getModuleForId(lotId_);

        // Store the capacity before settling
        uint256 capacity = module.remainingCapacity(lotId_);

        // Settle the auction
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = module.settle(lotId_);

        // Load routing data for the lot
        Routing storage routing = lotRouting[lotId_];

        // Check if the auction settled
        // If so, calculate fees, handle partial bid, transfer proceeds + (possible) refund to seller, and curator fee
        if (settlement.totalIn > 0 && settlement.totalOut > 0) {
            uint256 totalIn = settlement.totalIn;

            // Load curator data and calculate fee (excluding any refunds of capacity)
            FeeData storage feeData = lotFees[lotId_];

            // Store the protocol and referrer fees
            // If this is not done, the amount that the seller receives could be modified after settlement
            {
                Keycode auctionKeycode = keycodeFromVeecode(routing.auctionReference);
                feeData.protocolFee = fees[auctionKeycode].protocol;
                feeData.referrerFee = fees[auctionKeycode].referrer;
            }

            uint256 curatorFeePayout =
                _calculatePayoutFees(feeData.curated, feeData.curatorFee, capacity);

            // Collect the payout from the seller
            // Any unutilised capacity and fees can be claimed in `claimProceeds()`
            if (routing.funding == 0) {
                routing.funding = capacity + curatorFeePayout;
                _collectPayout(lotId_, settlement.totalIn, capacity + curatorFeePayout, routing);
            }

            // Check if there was a partial fill and handle the payout + refund
            if (settlement.pfBidder != address(0)) {
                // Reconstruct bid amount from the settlement price and the amount out
                uint256 filledAmount =
                    Math.mulDivDown(settlement.pfPayout, totalIn, settlement.totalOut);

                // Allocate quote and protocol fees for bid
                _allocateQuoteFees(
                    feeData.protocolFee,
                    feeData.referrerFee,
                    settlement.pfReferrer,
                    routing.seller,
                    routing.quoteToken,
                    filledAmount
                );

                // Reduce funding by the payout amount
                unchecked {
                    routing.funding -= settlement.pfPayout;
                }

                // Reduce the total amount in by the refund amount
                // This is so that fees are not charged on the refunded amount
                unchecked {
                    totalIn -= settlement.pfRefund;
                }

                // Send refund and payout to the bidder
                Transfer.transfer(
                    routing.quoteToken, settlement.pfBidder, settlement.pfRefund, false
                );
                _sendPayout(
                    lotId_, settlement.pfBidder, settlement.pfPayout, routing, auctionOutput
                );
            }

            // If the lot is under capacity, adjust the curator payout
            if (settlement.totalOut < capacity && curatorFeePayout > 0) {
                uint256 capacityRefund = capacity - settlement.totalOut;

                uint256 feeRefund = Math.mulDivDown(curatorFeePayout, capacityRefund, capacity);
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
                _sendPayout(lotId_, feeData.curator, curatorFeePayout, routing, auctionOutput);
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
    function claimProceeds(uint96 lotId_) external override nonReentrant {
        // Validation
        _isLotValid(lotId_);

        // Call auction module to validate and update data
        AuctionModule module = getModuleForId(lotId_);
        (uint256 purchased_, uint256 sold_, uint256 payoutSent_) = module.claimProceeds(lotId_);

        // Load data for the lot
        Routing storage routing = lotRouting[lotId_];

        // Calculate the referrer and protocol fees for the amount in
        // Fees are not allocated until the user claims their payout so that we don't have to iterate through them here
        // If a referrer is not set, that portion of the fee defaults to the protocol
        uint256 totalInLessFees;
        {
            (, uint256 toProtocol) = calculateQuoteFees(
                lotFees[lotId_].protocolFee, lotFees[lotId_].referrerFee, false, purchased_
            );
            totalInLessFees = purchased_ - toProtocol;
        }

        // TODO implement hooks

        // Send payment in bulk to the seller
        _sendPayment(routing.seller, totalInLessFees, routing.quoteToken, routing.hooks);

        // Refund any unused capacity and curator fees to the seller
        // By this stage, a partial payout (if applicable) and curator fees have been paid, leaving only the payout amount (`totalOut`) remaining.
        uint256 prefundingRefund = routing.funding + payoutSent_ - sold_;
        routing.funding -= prefundingRefund;
        Transfer.transfer(routing.baseToken, routing.seller, prefundingRefund, false);
    }

    // ========== CURATION ========== //

    /// @notice     Accept curation request for a lot.
    /// @notice     Access controlled. Must be proposed curator for lot.
    /// @dev        This function reverts if:
    ///             - the lot ID is invalid
    ///             - the caller is not the proposed curator
    ///             - the auction has ended or been cancelled
    ///             - the curator fee is not set
    ///             - the auction is prefunded and the fee cannot be collected
    ///             - re-entrancy is detected
    ///
    /// @param     lotId_       Lot ID
    function curate(uint96 lotId_) external nonReentrant {
        _isLotValid(lotId_);

        FeeData storage feeData = lotFees[lotId_];

        // Check that the caller is the proposed curator
        if (msg.sender != feeData.curator) revert NotPermitted(msg.sender);

        // Check that the curator has not already approved the auction
        if (feeData.curated) revert InvalidState();

        // Check that the auction has not ended or been cancelled
        AuctionModule module = getModuleForId(lotId_);
        if (module.hasEnded(lotId_) == true) revert InvalidState();

        Routing storage routing = lotRouting[lotId_];

        // Set the curator as approved
        feeData.curated = true;
        feeData.curatorFee = fees[keycodeFromVeecode(routing.auctionReference)].curator[msg.sender];

        // If the auction is pre-funded, transfer the fee amount from the seller
        if (routing.funding > 0) {
            // Calculate the fee amount based on the remaining capacity (must be in base token if auction is pre-funded)
            uint256 curatorFeePayout = _calculatePayoutFees(
                feeData.curated, feeData.curatorFee, module.remainingCapacity(lotId_)
            );

            // Increment the funding
            // Cannot overflow, as capacity is bounded by uint96 and the curator fee has a maximum percentage
            unchecked {
                routing.funding += curatorFeePayout;
            }

            // Don't need to check for fee on transfer here because it was checked on auction creation
            Transfer.transferFrom(
                routing.baseToken, routing.seller, address(this), curatorFeePayout, false
            );
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
        uint96 lotId_,
        uint256 amount_,
        ERC20 quoteToken_,
        IHooks hooks_,
        Transfer.Permit2Approval memory permit2Approval_
    ) internal {
        // Call pre hook on hooks contract if provided
        if (address(hooks_) != address(0)) {
            hooks_.pre(lotId_, amount_);
        }

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
    /// @param      hooks_          Hooks contract to call (optional)
    function _sendPayment(
        address lotOwner_,
        uint256 amount_,
        ERC20 quoteToken_,
        IHooks hooks_
    ) internal {
        Transfer.transfer(
            quoteToken_, address(hooks_) == address(0) ? lotOwner_ : address(hooks_), amount_, false
        );
    }

    /// @notice     Collects the payout token from the seller
    /// @dev        This function handles the following:
    ///             1. Calls the mid hook on the hooks contract (if provided)
    ///             2. Transfers the payout token from the seller
    ///
    ///             This function reverts if:
    ///             - Approval has not been granted to transfer the payout token
    ///             - The seller does not have sufficient balance of the payout token
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
        uint96 lotId_,
        uint256 paymentAmount_,
        uint256 payoutAmount_,
        Routing memory routingParams_
    ) internal {
        // Get the balance of the payout token before the transfer
        ERC20 baseToken = routingParams_.baseToken;

        // Call mid hook on hooks contract if provided
        if (address(routingParams_.hooks) != address(0)) {
            uint256 balanceBefore = baseToken.balanceOf(address(this));

            // The mid hook is expected to transfer the payout token to this contract
            routingParams_.hooks.mid(lotId_, paymentAmount_, payoutAmount_);

            // Check that the mid hook transferred the expected amount of payout tokens
            if (baseToken.balanceOf(address(this)) < balanceBefore + payoutAmount_) {
                revert InvalidHook();
            }
        }
        // Otherwise fallback to a standard ERC20 transfer
        else {
            Transfer.transferFrom(
                baseToken, routingParams_.seller, address(this), payoutAmount_, true
            );
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
        uint96 lotId_,
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

            // Lookup condensor module from combination of auction and derivative types
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

        // Call post hook on hooks contract if provided
        if (address(routingParams_.hooks) != address(0)) {
            routingParams_.hooks.post(lotId_, payoutAmount_);
        }
    }

    // ========== FEE FUNCTIONS ========== //

    function _allocateQuoteFees(
        uint256 protocolFee_,
        uint256 referrerFee_,
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
