// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {IBatchAuction} from "src/interfaces/modules/IBatchAuction.sol";
import {IBatchAuctionHouse} from "src/interfaces/IBatchAuctionHouse.sol";

// Internal libraries
import {Transfer} from "src/lib/Transfer.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

// External libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

// Auctions
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {AuctionModule} from "src/modules/Auction.sol";
import {BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";

import {fromVeecode} from "src/modules/Keycode.sol";

/// @title      BatchAuctionHouse
/// @notice     As its name implies, the BatchAuctionHouse is where batch auctions are created, bid on, and settled. The core protocol logic is implemented here.
contract BatchAuctionHouse is IBatchAuctionHouse, AuctionHouse {
    using Callbacks for ICallback;

    // ========== ERRORS ========== //

    error AmountLessThanMinimum();
    error InsufficientFunding();

    // ========== EVENTS ========== //

    event Bid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder, uint256 amount);

    event RefundBid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder);

    event ClaimBid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder);

    event Settle(uint96 indexed lotId);

    event Abort(uint96 indexed lotId);

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
    ///
    ///             This function reverts if:
    ///             - The specified auction module is not for batch auctions
    ///             - The capacity is in quote tokens
    function _auction(
        uint96 lotId_,
        RoutingParams calldata routing_,
        IAuction.AuctionParams calldata params_
    ) internal override returns (bool performedCallback) {
        // Validation

        // Ensure the auction type is batch
        AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(routing_.auctionType));
        if (auctionModule.auctionType() != IAuction.AuctionType.Batch) revert InvalidParams();

        // Batch auctions must be pre-funded

        // Capacity must be in base token for auctions that require pre-funding
        if (params_.capacityInQuote) revert InvalidParams();

        // Store pre-funding information
        lotRouting[lotId_].funding = params_.capacity;

        ERC20 baseToken = ERC20(routing_.baseToken);

        // Handle funding from callback or seller as configured
        if (routing_.callbacks.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG)) {
            uint256 balanceBefore = baseToken.balanceOf(address(this));

            // The onCreate callback should transfer the base token to this contract
            _onCreateCallback(routing_, lotId_, params_.capacity, true);

            // Check that the hook transferred the expected amount of base tokens
            if (baseToken.balanceOf(address(this)) < balanceBefore + params_.capacity) {
                revert InvalidCallback();
            }
        }
        // Otherwise fallback to a standard ERC20 transfer and then call the onCreate callback
        else {
            Transfer.transferFrom(baseToken, msg.sender, address(this), params_.capacity, true);
            _onCreateCallback(routing_, lotId_, params_.capacity, false);
        }

        // Return true to indicate that the callback was performed
        return true;
    }

    /// @inheritdoc AuctionHouse
    /// @dev        Handles cancellation of a batch auction lot.
    ///
    ///             This function performs the following:
    ///             - Refunds the base token to the seller (or callback)
    ///             - Calls the onCancel callback, if configured
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
            ERC20(routing.baseToken),
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
    /// @dev        Handles curation approval for a batch auction lot.
    ///
    ///             This function performs the following:
    ///             - Transfers the required base tokens from the seller (or callback)
    ///             - Calls the onCurate callback, if configured
    function _curate(
        uint96 lotId_,
        uint256 curatorFeePayout_,
        bytes calldata callbackData_
    ) internal override returns (bool performedCallback) {
        Routing storage routing = lotRouting[lotId_];

        // Increment the funding
        routing.funding += curatorFeePayout_;

        ERC20 baseToken = ERC20(routing.baseToken);

        // If the callbacks contract is configured to send base tokens, then source the fee from the callbacks contract
        // Otherwise, transfer from the auction owner
        if (Callbacks.hasPermission(routing.callbacks, Callbacks.SEND_BASE_TOKENS_FLAG)) {
            uint256 balanceBefore = baseToken.balanceOf(address(this));

            // The onCurate callback is expected to transfer the base tokens
            Callbacks.onCurate(routing.callbacks, lotId_, curatorFeePayout_, true, callbackData_);

            // Check that the callback transferred the expected amount of base tokens
            if (baseToken.balanceOf(address(this)) < balanceBefore + curatorFeePayout_) {
                revert InvalidCallback();
            }
        } else {
            // Don't need to check for fee on transfer here because it was checked on auction creation
            Transfer.transferFrom(
                baseToken, routing.seller, address(this), curatorFeePayout_, false
            );

            // Call the onCurate callback
            Callbacks.onCurate(routing.callbacks, lotId_, curatorFeePayout_, false, callbackData_);
        }

        // Calls the callback
        return true;
    }

    // ========== BID, REFUND, CLAIM ========== //

    /// @inheritdoc IBatchAuctionHouse
    /// @dev        This function performs the following:
    ///             - Validates the lot ID
    ///             - Records the bid on the auction module
    ///             - Transfers the quote token from the caller
    ///             - Calls the onBid callback
    ///
    ///             This function reverts if:
    ///             - `params_.lotId` is invalid
    ///             - The auction module reverts when creating a bid
    ///             - The quote token transfer fails
    ///             - Re-entrancy is detected
    function bid(
        BidParams memory params_,
        bytes calldata callbackData_
    ) external override nonReentrant returns (uint64 bidId) {
        _isLotValid(params_.lotId);

        // Set bidder to msg.sender if blank
        address bidder = params_.bidder == address(0) ? msg.sender : params_.bidder;

        // Record the bid on the auction module
        // The module will determine if the bid is valid - minimum bid size, minimum price, auction status, etc
        bidId = getBatchModuleForId(params_.lotId).bid(
            params_.lotId, bidder, params_.referrer, params_.amount, params_.auctionData
        );

        // Transfer the quote token from the caller
        // Note this transfers from the caller, not the bidder.
        // It allows for "bid on behalf of" functionality,
        // but if you bid for someone else, they will get the
        // payout and refund while you will pay initially.
        _collectPayment(
            params_.amount,
            ERC20(lotRouting[params_.lotId].quoteToken),
            Transfer.decodePermit2Approval(params_.permit2Data)
        );

        // Call the onBid callback
        Callbacks.onBid(
            lotRouting[params_.lotId].callbacks,
            params_.lotId,
            bidId,
            bidder, // Bidder is the buyer, should also be checked against any allowlist, if applicable
            params_.amount,
            callbackData_
        );

        // Emit event
        emit Bid(params_.lotId, bidId, bidder, params_.amount);

        return bidId;
    }

    /// @inheritdoc IBatchAuctionHouse
    /// @dev        This function performs the following:
    ///             - Validates the lot ID
    ///             - Refunds the bid on the auction module
    ///             - Transfers the quote token to the bidder
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The auction module reverts when cancelling the bid
    ///             - Re-entrancy is detected
    function refundBid(
        uint96 lotId_,
        uint64 bidId_,
        uint256 index_
    ) external override nonReentrant {
        _isLotValid(lotId_);

        // Transfer the quote token to the bidder
        // The ownership of the bid has already been verified by the auction module
        Transfer.transfer(
            ERC20(lotRouting[lotId_].quoteToken),
            msg.sender,
            // Refund the bid on the auction module
            // The auction module is responsible for validating the bid and authorizing the caller
            getBatchModuleForId(lotId_).refundBid(lotId_, bidId_, index_, msg.sender),
            false
        );

        // Emit event
        emit RefundBid(lotId_, bidId_, msg.sender);
    }

    /// @inheritdoc IBatchAuctionHouse
    /// @dev        This function performs the following:
    ///             - Validates the lot ID
    ///             - Claims the bids on the auction module
    ///             - Allocates the fees for each successful bid
    ///             - Transfers the payout and/or refund to each bidder
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The auction module reverts when claiming the bids
    ///             - Re-entrancy is detected
    function claimBids(uint96 lotId_, uint64[] calldata bidIds_) external override nonReentrant {
        _isLotValid(lotId_);

        // Claim the bids on the auction module
        // The auction module is responsible for validating the bid and authorizing the caller
        (IBatchAuction.BidClaim[] memory bidClaims, bytes memory auctionOutput) =
            getBatchModuleForId(lotId_).claimBids(lotId_, bidIds_);

        // Load routing data for the lot
        Routing storage routing = lotRouting[lotId_];
        ERC20 quoteToken = ERC20(routing.quoteToken);

        // Load fee data
        uint48 protocolFee = lotFees[lotId_].protocolFee;
        uint48 referrerFee = lotFees[lotId_].referrerFee;

        // Iterate through the bid claims and handle each one
        uint256 bidClaimsLen = bidClaims.length;
        for (uint256 i = 0; i < bidClaimsLen; i++) {
            IBatchAuction.BidClaim memory bidClaim = bidClaims[i];

            // If payout is greater than zero, then the bid was filled.
            // However, due to partial fills, there can be both a payout and a refund
            // If payout is zero, then the bid was not filled and the paid amount should be refunded

            if (bidClaim.payout > 0) {
                // Allocate quote and protocol fees for bid
                _allocateQuoteFees(
                    protocolFee,
                    referrerFee,
                    bidClaim.referrer,
                    routing.seller,
                    quoteToken,
                    bidClaim.paid - bidClaim.refund // refund is included in paid
                );

                // Reduce funding by the payout amount
                unchecked {
                    routing.funding -= bidClaim.payout;
                }

                // Send the payout to the bidder
                _sendPayout(bidClaim.bidder, bidClaim.payout, routing, auctionOutput);
            }

            if (bidClaim.refund > 0) {
                // Refund the provided amount to the bidder
                // If the bid was not filled, the refund should be the full amount paid
                // If the bid was partially filled, the refund should be the difference
                // between the paid amount and the filled amount
                Transfer.transfer(quoteToken, bidClaim.bidder, bidClaim.refund, false);
            }

            // Emit event
            emit ClaimBid(lotId_, bidIds_[i], bidClaim.bidder);
        }
    }

    /// @inheritdoc IBatchAuctionHouse
    /// @dev        This function handles the following:
    ///             - Settles the auction on the auction module
    ///             - Sends proceeds and/or refund to the seller
    ///             - Executes the onSettle callback
    ///             - Allocates the curator fee to the curator
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The auction module reverts when settling the auction
    ///             - Re-entrancy is detected
    function settle(
        uint96 lotId_,
        uint256 num_,
        bytes calldata callbackData_
    )
        external
        override
        nonReentrant
        returns (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput)
    {
        // Validation
        _isLotValid(lotId_);

        // Settle the auction
        uint256 capacity;
        {
            // Settle the lot on the auction module and get the winning bids
            // Reverts if the auction cannot be settled yet
            BatchAuctionModule module = getBatchModuleForId(lotId_);
            (totalIn, totalOut, capacity, finished, auctionOutput) = module.settle(lotId_, num_);

            // Return early if not finished
            if (finished == false) {
                return (totalIn, totalOut, finished, auctionOutput);
            }
        }

        // If the settlement is complete, then proceed with payouts, refunds, and callbacks
        // Load data for the lot
        Routing storage routing = lotRouting[lotId_];
        FeeData storage feeData = lotFees[lotId_];

        // Calculate the referrer and protocol fees for the amount in
        // Fees are not allocated until the user claims their payout so that we don't have to iterate through them here
        // If a referrer is not set, that portion of the fee defaults to the protocol
        uint256 totalInLessFees;
        {
            (, uint256 toProtocol) =
                calculateQuoteFees(feeData.protocolFee, feeData.referrerFee, false, totalIn);
            unchecked {
                totalInLessFees = totalIn - toProtocol;
            }
        }

        // Send payment in bulk to the address dictated by the callbacks address
        // If the callbacks contract is configured to receive quote tokens, send the quote tokens to the callbacks contract and call the onSettle callback
        // If not, send the quote tokens to the seller and call the onSettle callback
        _sendPayment(routing.seller, totalInLessFees, ERC20(routing.quoteToken), routing.callbacks);

        // Refund any unused capacity and curator fees to the address dictated by the callbacks address
        // Additionally, bidders are able to claim before the seller, so the funding isn't the right value
        // to use for the refund. Therefore, we use capacity, which is not decremented when batch auctions
        // are settled, minus the amount sold. Then, we add any unearned curator payout.
        uint256 prefundingRefund;
        {
            // Calculate the curator fee and allocate the fees to be claimed
            uint256 curatorPayout =
                _calculatePayoutFees(feeData.curated, feeData.curatorFee, totalOut);

            // If the curator payout is not zero, allocate it
            if (curatorPayout > 0) {
                // If the payout is a derivative, mint the derivative directly to the curator
                // Otherwise, allocate the fee using the internal rewards mechanism
                if (fromVeecode(routing.derivativeReference) != bytes7("")) {
                    // Mint the derivative to the curator
                    _sendPayout(feeData.curator, curatorPayout, routing, auctionOutput);
                } else {
                    // Allocate the curator fee to be claimed
                    rewards[feeData.curator][ERC20(routing.baseToken)] += curatorPayout;
                }

                // Decrease the funding amount
                unchecked {
                    routing.funding -= curatorPayout;
                }
            }

            uint256 maxCuratorPayout =
                _calculatePayoutFees(feeData.curated, feeData.curatorFee, capacity);
            prefundingRefund = capacity - totalOut + maxCuratorPayout - curatorPayout;
        }
        unchecked {
            routing.funding -= prefundingRefund;
        }
        Transfer.transfer(
            ERC20(routing.baseToken),
            _getAddressGivenCallbackBaseTokenFlag(routing.callbacks, routing.seller),
            prefundingRefund,
            false
        );

        // Call the onSettle callback
        Callbacks.onSettle(
            routing.callbacks, lotId_, totalInLessFees, prefundingRefund, callbackData_
        );

        // Emit event
        emit Settle(lotId_);
    }

    /// @inheritdoc IBatchAuctionHouse
    /// @dev        This function handles the following:
    ///             - Validates the lot id
    ///             - Aborts the auction on the auction module
    ///             - Refunds prefunding (in base tokens) to the seller
    ///             - Calls the onCancel callback
    ///
    ///             This function reverts if:
    ///             - The lot ID is invalid
    ///             - The auction module reverts when aborting the auction
    ///             - The refund amount is zero
    ///
    ///             Note that this function will not revert if the `onCancel` callback reverts.
    ///
    /// @param      lotId_   The lot ID to abort
    function abort(uint96 lotId_) external override nonReentrant {
        // Validation
        _isLotValid(lotId_);

        // Call the abort function on the auction module to update the auction state
        getBatchModuleForId(lotId_).abort(lotId_);

        // Cache the funding value to use as the refund and set the funding to 0
        Routing storage routing = lotRouting[lotId_];
        uint256 refund = routing.funding;
        if (refund == 0) revert InsufficientFunding();
        routing.funding = 0;

        // Send the base token refund to the seller or callbacks contract
        Transfer.transfer(
            ERC20(lotRouting[lotId_].baseToken),
            _getAddressGivenCallbackBaseTokenFlag(
                lotRouting[lotId_].callbacks, lotRouting[lotId_].seller
            ),
            refund,
            false
        );

        // If there is a callback configured, call the onCancel callback
        // This is necessary as an auction lot configured with a callback that
        // sends base tokens will have the base tokens sent to the callback contract.
        // Calling onCancel offers the opportunity for the auction owner to handle
        // the refund of the base tokens.
        if (lotRouting[lotId_].callbacks != ICallback(address(0))) {
            // Assemble the calldata
            bytes memory onCancelCalldata = abi.encodeWithSelector(
                ICallback.onCancel.selector,
                lotId_,
                refund,
                lotRouting[lotId_].callbacks.hasPermission(Callbacks.SEND_BASE_TOKENS_FLAG),
                abi.encode("")
            );

            // Call the onCancel callback, but ignore the return value
            // As it is a low-level call, it will not revert on failure
            // This prevents an auction owner from blocking an abort by reverting in the callback
            address(lotRouting[lotId_].callbacks).call(onCancelCalldata);
        }

        emit Abort(lotId_);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function getBatchModuleForId(uint96 lotId_) public view returns (BatchAuctionModule) {
        return BatchAuctionModule(address(_getAuctionModuleForId(lotId_)));
    }
}
