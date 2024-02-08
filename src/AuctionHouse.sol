/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";

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
    function bid(BidParams memory params_) external virtual returns (uint96 bidId);

    /// @notice     Cancel a bid on a lot in a batch auction
    /// @dev        The implementing function must perform the following:
    ///             1. Validate the bid
    ///             2. Pass the request to the auction module to validate and update data
    ///             3. Send the refund to the bidder
    ///
    /// @param      lotId_          Lot ID
    /// @param      bidId_          Bid ID
    function cancelBid(uint96 lotId_, uint96 bidId_) external virtual;

    /// @notice     Settle a batch auction
    /// @notice     This function is used for versions with on-chain storage and bids and local settlement
    function settle(uint96 lotId_) external virtual;
}

/// @title      AuctionHouse
/// @notice     As its name implies, the AuctionHouse is where auctions are created, bid on, and settled. The core protocol logic is implemented here.
contract AuctionHouse is Auctioneer, Router, FeeManager {
    /// Implement the router functionality here since it combines all of the base functionality

    // ========== ERRORS ========== //

    error AmountLessThanMinimum();

    error InvalidBidder(address bidder_);

    error Broken_Invariant();

    // ========== EVENTS ========== //

    event Purchase(
        uint96 indexed lotId,
        address indexed buyer,
        address referrer,
        uint256 amount,
        uint256 payout
    );

    event Bid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder, uint256 amount);

    event CancelBid(uint96 indexed lotId, uint96 indexed bidId, address indexed bidder);

    event Settle(uint96 indexed lotId);

    // ========== STATE VARIABLES ========== //

    address internal immutable _PERMIT2;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address protocol_,
        address permit2_
    ) FeeManager(protocol_) WithModules(msg.sender) {
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
            revert InvalidBidder(msg.sender);
        }

        // Calculate quote fees for purchase
        uint256 amountLessFees = params_.amount
            - _allocateQuoteFees(
                keycodeFromVeecode(routing.auctionReference),
                params_.referrer,
                routing.owner,
                routing.quoteToken,
                params_.amount
            );

        // Send purchase to auction house and get payout plus any extra output
        bytes memory auctionOutput;
        (payoutAmount, auctionOutput) = getModuleForId(params_.lotId).purchase(
            params_.lotId, amountLessFees, params_.auctionData
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

        // Send payment to auction owner
        _sendPayment(routing.owner, amountLessFees, routing.quoteToken, routing.hooks);

        // Calculate the curator fee (if applicable)
        Curation storage curation = lotCuration[params_.lotId];
        uint256 curatorFee;
        if (curation.curated) {
            curatorFee = _calculatePayoutFees(
                keycodeFromVeecode(routing.auctionReference), curation.curator, payoutAmount
            );
        }

        // Collect payout from auction owner
        _collectPayout(params_.lotId, amountLessFees, payoutAmount + curatorFee, routing);

        // Send payout to recipient

        // Decrease the prefunding amount (if applicable)
        if (routing.prefunding > 0) {
            // Check invariant
            if (routing.prefunding < payoutAmount) revert Broken_Invariant();
            unchecked {
                routing.prefunding -= payoutAmount;
            }
        }

        _sendPayout(params_.lotId, params_.recipient, payoutAmount, routing, auctionOutput);

        // Send curator fee to curator
        if (curatorFee > 0) {
            // Decrease the prefunding amount
            if (routing.prefunding > 0) {
                // Check invariant
                if (routing.prefunding < curatorFee) revert Broken_Invariant();
                unchecked {
                    routing.prefunding -= curatorFee;
                }
            }

            _sendPayout(params_.lotId, curation.curator, curatorFee, routing, auctionOutput);
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
    function bid(BidParams memory params_) external override nonReentrant returns (uint96) {
        _isLotValid(params_.lotId);

        // Load routing data for the lot
        Routing memory routing = lotRouting[params_.lotId];

        // Determine if the bidder is authorized to bid
        if (!_isAllowed(routing.allowlist, params_.lotId, msg.sender, params_.allowlistProof)) {
            revert InvalidBidder(msg.sender);
        }

        // Record the bid on the auction module
        // The module will determine if the bid is valid - minimum bid size, minimum price, auction status, etc
        uint96 bidId = getModuleForId(params_.lotId).bid(
            params_.lotId,
            msg.sender,
            params_.recipient,
            params_.referrer,
            params_.amount,
            params_.auctionData
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
    function cancelBid(uint96 lotId_, uint96 bidId_) external override nonReentrant {
        _isLotValid(lotId_);

        // Cancel the bid on the auction module
        // The auction module is responsible for validating the bid and authorizing the caller
        uint256 refundAmount = getModuleForId(lotId_).cancelBid(lotId_, bidId_, msg.sender);

        // Transfer the quote token to the bidder
        // The ownership of the bid has already been verified by the auction module
        Transfer.transfer(lotRouting[lotId_].quoteToken, msg.sender, refundAmount, false);

        // Emit event
        emit CancelBid(lotId_, bidId_, msg.sender);
    }

    /// @inheritdoc Router
    /// @dev        This function handles the following:
    ///             - Settles the auction on the auction module
    ///             - Calculates the payout amount, taking partial fill into consideration
    ///             - Calculates the fees taken on the quote token
    ///             - Collects the payout from the auction owner (if necessary)
    ///             - Sends the payout to each bidder
    ///             - Sends the payment to the auction owner
    ///             - Sends the refund to the bidder if the last bid was a partial fill
    ///             - Refunds any unused base token to the auction owner
    ///
    ///             This function reverts if:
    ///             - the lot ID is invalid
    ///             - the auction module reverts when settling the auction
    ///             - transferring the quote token to the auction owner fails
    ///             - collecting the payout from the auction owner fails
    ///             - sending the payout to each bidder fails
    ///             - re-entrancy is detected
    function settle(uint96 lotId_) external override nonReentrant {
        // Validation
        _isLotValid(lotId_);

        // Settle the lot on the auction module and get the winning bids
        // Reverts if the auction cannot be settled yet
        AuctionModule module = getModuleForId(lotId_);

        // Store the capacity remaining before settling
        uint256 remainingCapacity = module.remainingCapacity(lotId_);

        // Settle the auction
        (Auction.Bid[] memory winningBids, bytes memory auctionOutput) = module.settle(lotId_);

        // Load routing data for the lot
        Routing storage routing = lotRouting[lotId_];

        // Calculate the payout amount, handling partial fills
        uint256 lastBidRefund;
        address lastBidder;
        uint256 totalAmountOut = remainingCapacity;
        {
            uint256 bidCount = winningBids.length;
            uint256 payoutRemaining = remainingCapacity;
            for (uint256 i; i < bidCount; i++) {
                uint256 payoutAmount = winningBids[i].minAmountOut;

                // If the bid is the last and is a partial fill, then calculate the amount to send
                if (i == bidCount - 1 && payoutAmount > payoutRemaining) {
                    // Amend the bid to the amount remaining
                    winningBids[i].minAmountOut = payoutRemaining;

                    // Calculate the refund amount in terms of the quote token
                    uint256 payoutUnfulfilled = 1e18 - payoutRemaining * 1e18 / payoutAmount;
                    uint256 refundAmount = winningBids[i].amount * payoutUnfulfilled / 1e18;
                    lastBidRefund = refundAmount;
                    lastBidder = winningBids[i].bidder;

                    // Check that the refund amount is not greater than the bid amount
                    if (refundAmount > winningBids[i].amount) {
                        revert Broken_Invariant();
                    }

                    // Adjust the payment amount (otherwise fees will be charged)
                    unchecked {
                        winningBids[i].amount -= refundAmount;
                    }

                    // Decrement the remaining payout
                    payoutRemaining = 0;
                    break;
                }

                // Make sure the invariant isn't broken
                if (payoutAmount > payoutRemaining) {
                    revert Broken_Invariant();
                }

                // Decrement the remaining payout
                unchecked {
                    payoutRemaining -= payoutAmount;
                }
            }

            // If payout remaining is not zero, reduce the total amount out
            if (payoutRemaining > 0) {
                totalAmountOut -= payoutRemaining;
            }
        }

        // Calculate fees
        uint256 totalAmountInLessFees;
        {
            (uint256 totalAmountIn, uint256 totalFees) = _allocateQuoteFees(
                keycodeFromVeecode(routing.auctionReference),
                winningBids,
                routing.owner,
                routing.quoteToken
            );
            totalAmountInLessFees = totalAmountIn - totalFees;
        }

        // Assumes that payment has already been collected for each bid

        // Collect payout in bulk from the auction owner
        {
            // Calculate curator fee (if applicable)
            Curation storage curation = lotCuration[lotId_];
            uint256 curatorFee;
            {
                if (curation.curated) {
                    curatorFee = _calculatePayoutFees(
                        keycodeFromVeecode(routing.auctionReference),
                        curation.curator,
                        totalAmountOut
                    );
                }
            }

            _collectPayout(lotId_, totalAmountInLessFees, totalAmountOut + curatorFee, routing);

            // Send curator fee to curator (if applicable)
            if (curatorFee > 0) {
                if (routing.prefunding > 0) {
                    if (routing.prefunding < curatorFee) revert Broken_Invariant();

                    // Update the remaining prefunding
                    unchecked {
                        routing.prefunding -= curatorFee;
                    }
                }

                _sendPayout(lotId_, curation.curator, curatorFee, routing, auctionOutput);
            }
        }

        // Handle payouts to bidders
        {
            uint256 prefundingRemaining = routing.prefunding;
            uint256 payoutRemaining = remainingCapacity;
            uint256 bidCount = winningBids.length;
            for (uint256 i; i < bidCount; i++) {
                uint256 currentBidOut = winningBids[i].minAmountOut;

                // Send payout to each bid's recipient
                _sendPayout(lotId_, winningBids[i].recipient, currentBidOut, routing, auctionOutput);

                // Make sure the invariant isn't broken
                if (currentBidOut > payoutRemaining) {
                    revert Broken_Invariant();
                }

                // Decrement the remaining payout
                payoutRemaining -= currentBidOut;

                // Update prefunding
                if (routing.prefunding > 0) {
                    if (prefundingRemaining < currentBidOut) {
                        revert Broken_Invariant();
                    }

                    // Update the remaining prefunding
                    unchecked {
                        prefundingRemaining -= currentBidOut;
                    }
                }
            }

            // Handle the refund to the auction owner for any unused base token capacity
            if (prefundingRemaining > 0) {
                routing.prefunding = 0;

                Transfer.transfer(routing.baseToken, routing.owner, prefundingRemaining, false);
            }
            // If the prefunding was previously set, zero it
            else if (routing.prefunding > 0) {
                routing.prefunding = 0;
            }
        }

        // Send payment in bulk to auction owner
        _sendPayment(routing.owner, totalAmountInLessFees, routing.quoteToken, routing.hooks);

        // Handle the refund to the bidder if the last bid was a partial fill
        if (lastBidRefund > 0 && lastBidder != address(0)) {
            Transfer.transfer(routing.quoteToken, lastBidder, lastBidRefund, false);
        }

        // Emit event
        emit Settle(lotId_);
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

        Routing storage routing = lotRouting[lotId_];
        Curation storage curation = lotCuration[lotId_];

        // Check that the caller is the proposed curator
        if (msg.sender != curation.curator) revert NotPermitted(msg.sender);

        // Check that the curator has not already approved the auction
        if (curation.curated) revert InvalidState();

        // Check that the auction has not ended or been cancelled
        (, uint48 conclusion,,,, uint256 capacity,,) = getModuleForId(lotId_).lotData(lotId_);
        if (uint48(block.timestamp) >= conclusion || capacity == 0) revert InvalidState();

        Keycode auctionType = keycodeFromVeecode(routing.auctionReference);

        // Check that the curator fee is set
        if (fees[auctionType].curator[msg.sender] == 0) revert InvalidFee();

        // Set the curator as approved
        curation.curated = true;

        // If the auction is pre-funded, transfer the fee amount from the owner
        if (routing.prefunding > 0) {
            // Calculate the fee amount based on the remaining capacity (must be in base token if auction is pre-funded)
            uint256 fee = _calculatePayoutFees(auctionType, msg.sender, capacity);

            // Increment the prefunding
            routing.prefunding += fee;

            // Don't need to check for fee on transfer here because it was checked on auction creation
            Transfer.transferFrom(routing.baseToken, routing.owner, address(this), fee, false);
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
        // TODO should we have hard-coded maximums for these fees?
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
        Transfer.transfer(
            quoteToken_, address(hooks_) == address(0) ? lotOwner_ : address(hooks_), amount_, false
        );
    }

    /// @notice     Collects the payout token from the auction owner
    /// @dev        This function handles the following:
    ///             1. Calls the mid hook on the hooks contract (if provided)
    ///             2. Transfers the payout token from the auction owner
    ///             2a. If the auction is pre-funded, then the transfer is skipped
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
        uint96 lotId_,
        uint256 paymentAmount_,
        uint256 payoutAmount_,
        Routing memory routingParams_
    ) internal {
        // If pre-funded, then the payout token is already in this contract
        if (routingParams_.prefunding > 0) {
            return;
        }

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
                baseToken, routingParams_.owner, address(this), payoutAmount_, true
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
        Keycode auctionType_,
        address referrer_,
        address owner_,
        ERC20 quoteToken_,
        uint256 amount_
    ) internal returns (uint256 totalFees) {
        // Check if there is a referrer
        bool hasReferrer = referrer_ != address(0) && referrer_ != owner_;

        // Calculate fees for purchase
        (uint256 toReferrer, uint256 toProtocol) =
            calculateQuoteFees(auctionType_, hasReferrer, amount_);

        // Update fee balances if non-zero
        if (toReferrer > 0) rewards[referrer_][quoteToken_] += toReferrer;
        if (toProtocol > 0) rewards[_protocol][quoteToken_] += toProtocol;

        return toReferrer + toProtocol;
    }

    function _allocateQuoteFees(
        Keycode auctionType_,
        Auction.Bid[] memory bids_,
        address owner_,
        ERC20 quoteToken_
    ) internal returns (uint256 totalAmountIn, uint256 totalFees) {
        // Calculate fees for purchase
        uint256 bidCount = bids_.length;
        uint256 totalProtocolFees;
        for (uint256 i; i < bidCount; i++) {
            // Determine if bid has a referrer
            bool hasReferrer = bids_[i].referrer != address(0) && bids_[i].referrer != owner_;

            // Calculate fees from bid amount
            (uint256 toReferrer, uint256 toProtocol) =
                calculateQuoteFees(auctionType_, hasReferrer, bids_[i].amount);

            // Update referrer fee balances if non-zero and increment the total protocol fee
            if (toReferrer > 0) {
                rewards[bids_[i].referrer][quoteToken_] += toReferrer;
            }
            totalProtocolFees += toProtocol;
            totalFees += toReferrer + toProtocol;

            // Increment total amount in
            totalAmountIn += bids_[i].amount;
        }

        // Update protocol fee if not zero
        if (totalProtocolFees > 0) rewards[_protocol][quoteToken_] += totalProtocolFees;
    }
}
