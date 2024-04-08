// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Transfer} from "src/lib/Transfer.sol";
import {FixedPointMathLib as Math} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";

import {
    Keycode, keycodeFromVeecode, WithModules
} from "src/modules/Modules.sol";

import {ICallback} from "src/interfaces/ICallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

/// @title      AtomicRouter
/// @notice     An interface to define the AtomicAuctionHouse's buyer-facing functions
abstract contract AtomicRouter {
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
        uint256 amount;
        uint256 minAmountOut;
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
    ) external virtual returns (uint256 payout);
}

/// @title      AtomicAuctionHouse
/// @notice     As its name implies, the AuctionHouse is where auctions are created, bid on, and settled. The core protocol logic is implemented here.
contract AtomicAuctionHouse is AuctionHouse, AtomicRouter {
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

    // ========== CONSTRUCTOR ========== //

    constructor(
        address owner_,
        address protocol_,
        address permit2_
    ) AuctionHouse(owner_, protocol_, permit2_) {}

    // ========== AUCTION MANAGEMENT ========== //

    function _auction(
        uint96,
        RoutingParams calldata,
        Auction.AuctionParams calldata
    ) internal override returns (bool performedCallback) {
        // No additional logic for atomic auctions.
        // They cannot be prefunded.
        return false;
    }

    // ========== PURCHASE ========== //

    /// @inheritdoc AtomicRouter
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
    ) external override nonReentrant returns (uint256 payoutAmount) {
        _isLotValid(params_.lotId);

        // Load routing data for the lot
        Routing storage routing = lotRouting[params_.lotId];

        // Calculate quote fees for purchase
        // Note: this enables protocol and referrer fees to be changed between purchases
        uint256 amountLessFees;
        {
            Keycode auctionKeycode = keycodeFromVeecode(routing.auctionReference);
            uint256 totalFees = _allocateQuoteFees(
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
        uint256 curatorFeePayout = _calculatePayoutFees(
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
}
