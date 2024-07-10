// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IAtomicAuctionHouse} from "src/interfaces/IAtomicAuctionHouse.sol";
import {ICallback} from "src/interfaces/ICallback.sol";

// External libraries
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Internal libaries
import {Transfer} from "src/lib/Transfer.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

// Auction
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {AuctionModule} from "src/modules/Auction.sol";
import {AtomicAuctionModule} from "src/modules/auctions/AtomicAuctionModule.sol";

/// @title      AtomicAuctionHouse
/// @notice     As its name implies, the AtomicAuctionHouse is where atomic auction lots are created and purchased. The core protocol logic is implemented here.
contract AtomicAuctionHouse is IAtomicAuctionHouse, AuctionHouse {
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

    /// @inheritdoc AuctionHouse
    function _auction(
        uint96,
        RoutingParams calldata routing_,
        IAuction.AuctionParams calldata
    ) internal view override returns (bool performedCallback) {
        // Validation

        // Ensure the auction type is atomic
        AuctionModule auctionModule = AuctionModule(_getLatestModuleIfActive(routing_.auctionType));
        if (auctionModule.auctionType() != IAuction.AuctionType.Atomic) revert InvalidParams();

        // Cannot be prefunded

        return false;
    }

    /// @inheritdoc AuctionHouse
    function _cancel(
        uint96,
        bytes calldata
    ) internal pure override returns (bool performedCallback) {
        // No additional logic for atomic auctions.
        // They are not prefunded.
        return false;
    }

    // ========== PURCHASE ========== //

    /// @dev        This function handles the following:
    ///             1. Calculates the fees for the purchase
    ///             2. Obtains the payout from the auction module
    ///             3. Transfers the purchase amount (quote token) from the caller
    ///             4. Transfers the purchase amount (quote token) to the seller
    ///             5. Transfers the payout and curator fee amounts (base token) from the seller or executes the callback
    ///             6. Transfers the payout amount (base token) to the recipient
    ///             7. Transfers the fee amount (base token) to the curator
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
    ///             - Re-entrancy is detected
    function _purchase(
        PurchaseParams memory params_,
        bytes calldata callbackData_
    ) internal returns (uint256 payoutAmount) {
        _isLotValid(params_.lotId);

        // Set recipient to msg.sender if blank
        address recipient = params_.recipient == address(0) ? msg.sender : params_.recipient;

        // Load routing data for the lot
        Routing storage routing = lotRouting[params_.lotId];

        // Calculate quote fees for purchase
        // Fees were cached on auction creation, so they are consistent for an auction
        uint256 amountLessFees;
        {
            uint256 totalFees = _allocateQuoteFees(
                lotFees[params_.lotId].protocolFee,
                lotFees[params_.lotId].referrerFee,
                params_.referrer,
                routing.seller,
                ERC20(routing.quoteToken),
                params_.amount
            );
            unchecked {
                amountLessFees = params_.amount - totalFees;
            }
        }

        // Send purchase to auction house and get payout plus any extra output
        bytes memory auctionOutput;
        (payoutAmount, auctionOutput) = AtomicAuctionModule(
            address(_getAuctionModuleForId(params_.lotId))
        ).purchase(params_.lotId, amountLessFees, params_.auctionData);

        // Check that payout is at least minimum amount out
        // @dev Moved the slippage check from the auction to the AuctionHouse to allow different routing and purchase logic
        if (payoutAmount < params_.minAmountOut) revert AmountLessThanMinimum();

        // Transfer the quote token from the caller
        // Note this transfers from the caller, not the recipient
        // It allows for "purchase on behalf of" functionality,
        // but if you purchase for someone else, they will get the
        // payout, while you will pay.
        _collectPayment(
            params_.amount,
            ERC20(routing.quoteToken),
            Transfer.decodePermit2Approval(params_.permit2Data)
        );

        // Send payment, this function handles routing of the quote tokens correctly
        _sendPayment(routing.seller, amountLessFees, ERC20(routing.quoteToken), routing.callbacks);

        // Calculate the curator fee (if applicable)
        uint256 curatorFeePayout = _calculatePayoutFees(
            lotFees[params_.lotId].curated, lotFees[params_.lotId].curatorFee, payoutAmount
        );

        // If callbacks contract is configured to send base tokens, then source the payout from the callbacks contract
        if (Callbacks.hasPermission(routing.callbacks, Callbacks.SEND_BASE_TOKENS_FLAG)) {
            uint256 balanceBefore = ERC20(routing.baseToken).balanceOf(address(this));

            Callbacks.onPurchase(
                routing.callbacks,
                params_.lotId,
                recipient, // Recipient is the buyer, should also be checked against any allowlist, if applicable
                amountLessFees,
                payoutAmount + curatorFeePayout,
                false, // Not prefunded. The onPurchase callback is expected to transfer the base tokens
                callbackData_
            );

            // Check that the mid hook transferred the expected amount of payout tokens
            if (
                ERC20(routing.baseToken).balanceOf(address(this))
                    < balanceBefore + payoutAmount + curatorFeePayout
            ) {
                revert InvalidCallback();
            }
        }
        // Otherwise, transfer directly from the auction owner
        // Still call the onPurchase callback to allow for custom logic
        else {
            Transfer.transferFrom(
                ERC20(routing.baseToken),
                routing.seller,
                address(this),
                payoutAmount + curatorFeePayout,
                true
            );

            // Call the onPurchase callback
            Callbacks.onPurchase(
                routing.callbacks,
                params_.lotId,
                recipient, // Recipient is the buyer, should also be checked against any allowlist, if applicable
                amountLessFees,
                payoutAmount + curatorFeePayout,
                true, // Already prefunded
                callbackData_
            );
        }

        // Send payout to recipient
        _sendPayout(recipient, payoutAmount, routing, auctionOutput);

        // Send curator fee to curator
        if (curatorFeePayout > 0) {
            _sendPayout(lotFees[params_.lotId].curator, curatorFeePayout, routing, auctionOutput);
        }

        // Emit event
        emit Purchase(params_.lotId, recipient, params_.referrer, params_.amount, payoutAmount);
    }

    /// @inheritdoc IAtomicAuctionHouse
    function purchase(
        PurchaseParams memory params_,
        bytes calldata callbackData_
    ) external override nonReentrant returns (uint256 payoutAmount) {
        payoutAmount = _purchase(params_, callbackData_);
    }

    /// @inheritdoc IAtomicAuctionHouse
    function multiPurchase(
        PurchaseParams[] memory params_,
        bytes[] calldata callbackData_
    ) external override nonReentrant returns (uint256[] memory payoutAmounts) {
        // Check that the arrays are the same length
        if (params_.length != callbackData_.length) revert InvalidParams();

        // Iterate through and make each purchase
        uint256 len = params_.length;
        payoutAmounts = new uint256[](len);
        for (uint256 i; i < len; i++) {
            payoutAmounts[i] = _purchase(params_[i], callbackData_[i]);
        }
    }

    // ========== CURATION ========== //

    /// @inheritdoc AuctionHouse
    function _curate(uint96, uint256, bytes calldata) internal virtual override returns (bool) {
        // No additional logic for atomic auctions.
        // They are not prefunded.
        return false;
    }
}
