// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Transfer} from "src/lib/Transfer.sol";
import {FixedPointMathLib as Math} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {Auction, AuctionModule} from "src/modules/Auction.sol";
import {BatchAuction, BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";
import {Keycode, keycodeFromVeecode} from "src/modules/Modules.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @title      BatchRouter
/// @notice     An interface to define the AuctionHouse's buyer-facing functions
abstract contract BatchRouter {
    // ========== DATA STRUCTURES ========== //

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
        uint256 amount;
        bytes auctionData;
        bytes permit2Data;
    }

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

/// @title      BatchAuctionHouse
/// @notice     As its name implies, the AuctionHouse is where auctions are created, bid on, and settled. The core protocol logic is implemented here.
contract BatchAuctionHouse is AuctionHouse, BatchRouter {
    using Callbacks for ICallback;

    // ========== ERRORS ========== //

    error AmountLessThanMinimum();
    error InsufficientFunding();

    // ========== EVENTS ========== //

    event Bid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder, uint256 amount);

    event RefundBid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder);

    event ClaimBid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder);

    event ClaimProceeds(uint96 indexed lotId, address indexed seller);

    event Settle(uint96 indexed lotId);

    // ========== STATE VARIABLES ========== //

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address protocol_,
        address permit2_
    ) AuctionHouse(owner_, protocol_, permit2_) {}

    // ========== AUCTION MANAGEMENT ========== //

    /// @inheritdoc AuctionHouse
    /// @dev        Handles auction creation for a batch auction.
    ///
    ///             This function performs the following:
    ///             - Performs additional validation
    ///             - Collects the payout token from the seller (prefunding)
    ///             - Calls the onCreate callback, if configured
    function _auction(
        uint96 lotId_,
        RoutingParams calldata routing_,
        Auction.AuctionParams calldata params_
    ) internal override returns (bool performedCallback) {
        // Validation

        // Ensure the auction type is atomic
        AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(routing_.auctionType));
        if (auctionModule.auctionType() != Auction.AuctionType.Batch) revert InvalidParams();

        // Batch auctions must be pre-funded

        // Capacity must be in base token for auctions that require pre-funding
        if (params_.capacityInQuote) revert InvalidParams();

        // Store pre-funding information
        lotRouting[lotId_].funding = params_.capacity;

        // Handle funding from callback or seller as configured
        if (routing_.callbacks.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG)) {
            uint256 balanceBefore = routing_.baseToken.balanceOf(address(this));

            // The onCreate callback should transfer the base token to this contract
            _onCreateCallback(routing_, lotId_, params_.capacity, true);

            // Check that the hook transferred the expected amount of base tokens
            if (routing_.baseToken.balanceOf(address(this)) < balanceBefore + params_.capacity) {
                revert InvalidCallback();
            }
        }
        // Otherwise fallback to a standard ERC20 transfer and then call the onCreate callback
        else {
            Transfer.transferFrom(
                routing_.baseToken, msg.sender, address(this), params_.capacity, true
            );
            _onCreateCallback(routing_, lotId_, params_.capacity, false);
        }

        // Return true to indicate that the callback was performed
        return true;
    }

    /// @inheritdoc AuctionHouse
    function _cancel(
        uint96 lotId_,
        bytes calldata callbackData_
    ) internal override returns (bool performedCallback) {
        // No additional validation needed

        // All batch auctions are prefunded
        Routing storage routing = lotRouting[lotId_];
        uint256 funding = routing.funding;

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

        return true;
    }

    // ========== CURATION ========== //

    /// @inheritdoc AuctionHouse
    function _curate(
        uint96 lotId_,
        uint256 curatorFeePayout_,
        bytes calldata callbackData_
    ) internal override returns (bool performedCallback) {
        Routing storage routing = lotRouting[lotId_];

        // Increment the funding
        routing.funding += curatorFeePayout_;

        // If the callbacks contract is configured to send base tokens, then source the fee from the callbacks contract
        // Otherwise, transfer from the auction owner
        if (Callbacks.hasPermission(routing.callbacks, Callbacks.SEND_BASE_TOKENS_FLAG)) {
            uint256 balanceBefore = routing.baseToken.balanceOf(address(this));

            // The onCurate callback is expected to transfer the base tokens
            Callbacks.onCurate(routing.callbacks, lotId_, curatorFeePayout_, true, callbackData_);

            // Check that the callback transferred the expected amount of base tokens
            if (routing.baseToken.balanceOf(address(this)) < balanceBefore + curatorFeePayout_) {
                revert InvalidCallback();
            }
        } else {
            // Don't need to check for fee on transfer here because it was checked on auction creation
            Transfer.transferFrom(
                routing.baseToken, routing.seller, address(this), curatorFeePayout_, false
            );

            // Call the onCurate callback
            Callbacks.onCurate(routing.callbacks, lotId_, curatorFeePayout_, false, callbackData_);
        }

        // Calls the callback
        return true;
    }

    // ========== BID, REFUND, CLAIM ========== //

    /// @inheritdoc BatchRouter
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
        bidId = _getBatchModuleForId(params_.lotId).bid(
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

    /// @inheritdoc BatchRouter
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
            _getBatchModuleForId(lotId_).refundBid(lotId_, bidId_, msg.sender),
            false
        );

        // Emit event
        emit RefundBid(lotId_, bidId_, msg.sender);
    }

    /// @inheritdoc BatchRouter
    /// @dev        This function reverts if:
    ///             - the lot ID is invalid
    ///             - the auction module reverts when claiming the bids
    ///             - re-entrancy is detected
    function claimBids(uint96 lotId_, uint64[] calldata bidIds_) external override nonReentrant {
        _isLotValid(lotId_);

        // Claim the bids on the auction module
        // The auction module is responsible for validating the bid and authorizing the caller
        (BatchAuction.BidClaim[] memory bidClaims, bytes memory auctionOutput) =
            _getBatchModuleForId(lotId_).claimBids(lotId_, bidIds_);

        // Load routing data for the lot
        Routing storage routing = lotRouting[lotId_];

        // Load fee data
        uint48 protocolFee = lotFees[lotId_].protocolFee;
        uint48 referrerFee = lotFees[lotId_].referrerFee;

        // Iterate through the bid claims and handle each one
        uint256 bidClaimsLen = bidClaims.length;
        for (uint256 i = 0; i < bidClaimsLen; i++) {
            BatchAuction.BidClaim memory bidClaim = bidClaims[i];

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

            // Emit event
            emit ClaimBid(lotId_, bidIds_[i], bidClaim.bidder);
        }
    }

    /// @inheritdoc BatchRouter
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
        BatchAuctionModule module = _getBatchModuleForId(lotId_);

        // Store the capacity before settling
        uint256 capacity = module.remainingCapacity(lotId_);

        // Settle the auction
        (BatchAuction.Settlement memory settlement, bytes memory auctionOutput) =
            module.settle(lotId_);

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

            uint256 curatorFeePayout =
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
                    Math.mulDivDown(settlement.pfPayout, settlement.totalIn, settlement.totalOut)
                );

                // Reduce funding by the payout amount
                unchecked {
                    routing.funding -= settlement.pfPayout;
                }

                // Send refund and payout to the bidder
                Transfer.transfer(
                    routing.quoteToken, settlement.pfBidder, settlement.pfRefund, false
                );
                _sendPayout(settlement.pfBidder, settlement.pfPayout, routing, auctionOutput);
            }

            // If the lot is under capacity, adjust the curator payout
            if (settlement.totalOut < capacity && curatorFeePayout > 0) {
                uint256 capacityRefund;
                unchecked {
                    capacityRefund = capacity - settlement.totalOut;
                }

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
                _sendPayout(feeData.curator, curatorFeePayout, routing, auctionOutput);
            }
        }

        // Emit event
        emit Settle(lotId_);
    }

    /// @inheritdoc BatchRouter
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
        (uint256 purchased_, uint256 sold_, uint256 payoutSent_) =
            _getBatchModuleForId(lotId_).claimProceeds(lotId_);

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
        uint256 prefundingRefund = routing.funding + payoutSent_ - sold_;
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

        // Emit event
        emit ClaimProceeds(lotId_, routing.seller);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _getBatchModuleForId(uint96 lotId_) internal view returns (BatchAuctionModule) {
        return BatchAuctionModule(address(_getModuleForId(lotId_)));
    }
}
