// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Interfaces
import {ICallback} from "src/interfaces/ICallback.sol";

// Internal libraries
import {Callbacks} from "src/lib/Callbacks.sol";

/// @title  BaseCallback
/// @notice This contract implements standard behaviours for callbacks to the Axis auction system.
///         Developers can extend this contract to implement custom logic for their callbacks.
abstract contract BaseCallback is ICallback {
    // ========== ERRORS ========== //

    error Callback_InvalidParams();
    error Callback_NotAuthorized();
    error Callback_NotImplemented();

    // ========== STATE VARIABLES ========== //

    /// @notice The AuctionHouse that this callback is linked to
    address public immutable AUCTION_HOUSE;

    /// @notice Records lot ids against their registration status
    mapping(uint96 => bool) public lotIdRegistered;

    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_, Callbacks.Permissions memory permissions_) {
        // Validate the permissions against the deployed address
        Callbacks.validateCallbacksPermissions(this, permissions_);

        // Set the auction house
        AUCTION_HOUSE = auctionHouse_;
    }

    // ========== MODIFIERS ========== //

    modifier onlyAuctionHouse() {
        if (msg.sender != AUCTION_HOUSE) revert Callback_NotAuthorized();
        _;
    }

    modifier onlyRegisteredLot(uint96 lotId_) {
        if (!lotIdRegistered[lotId_]) revert Callback_NotAuthorized();
        _;
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc ICallback
    function onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse returns (bytes4) {
        // Validate the lot registration
        if (lotIdRegistered[lotId_]) revert Callback_InvalidParams();

        // Set the lot ID as registered
        lotIdRegistered[lotId_] = true;

        // Call implementation specific logic
        // If prefund_ is true, then the AuctionHouse will expect the capacity_ of base tokens to be sent back
        _onCreate(lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, callbackData_);

        return this.onCreate.selector;
    }

    /// @notice Implementation-specifc logic for the onCreate callback
    /// @dev    This function should be overridden by the inheriting contract to implement custom logic. It is called at the end of the `onCreate()` callback function.
    ///
    /// @param  lotId_        The lot ID
    /// @param  seller_       The seller of the lot
    /// @param  baseToken_    The base token of the lot
    /// @param  quoteToken_   The quote token of the lot
    /// @param  capacity_     The capacity of the lot
    /// @param  prefund_      Whether the lot is prefunded
    /// @param  callbackData_ Additional data for the callback
    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual;

    /// @inheritdoc ICallback
    function onCancel(
        uint96 lotId_,
        uint256 refund_,
        bool prefunded_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        // If prefunded_ is true, then the refund_ will be sent prior to the call
        _onCancel(lotId_, refund_, prefunded_, callbackData_);

        return this.onCancel.selector;
    }

    /// @notice Implementation-specifc logic for the onCancel callback
    /// @dev    This function should be overridden by the inheriting contract to implement custom logic. It is called at the end of the `onCancel()` callback function.
    ///
    /// @param  lotId_        The lot ID
    /// @param  refund_       The refund amount
    /// @param  prefunded_    Whether the lot was prefunded
    /// @param  callbackData_ Additional data for the callback
    function _onCancel(
        uint96 lotId_,
        uint256 refund_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual;

    /// @inheritdoc ICallback
    function onCurate(
        uint96 lotId_,
        uint256 curatorFee_,
        bool prefund_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        // If prefund_ is true, then the AuctionHouse will expect the curatorFee_ of base tokens to be sent back
        _onCurate(lotId_, curatorFee_, prefund_, callbackData_);

        return this.onCurate.selector;
    }

    /// @notice Implementation-specifc logic for the onCurate callback
    /// @dev    This function should be overridden by the inheriting contract to implement custom logic. It is called at the end of the `onCurate()` callback function.
    ///
    /// @param  lotId_        The lot ID
    /// @param  curatorFee_   The curator fee
    /// @param  prefund_      Whether the lot is prefunded
    /// @param  callbackData_ Additional data for the callback
    function _onCurate(
        uint96 lotId_,
        uint256 curatorFee_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual;

    /// @inheritdoc ICallback
    function onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        // If not prefunded, the auction house will expect the payout_ to be sent
        _onPurchase(lotId_, buyer_, amount_, payout_, prefunded_, callbackData_);

        return this.onPurchase.selector;
    }

    /// @notice Implementation-specifc logic for the onPurchase callback
    /// @dev    This function should be overridden by the inheriting contract to implement custom logic. It is called at the end of the `onPurchase()` callback function.
    /// @param  lotId_        The lot ID
    /// @param  buyer_        The buyer submitting the bid
    /// @param  amount_       The amount of the bid
    /// @param  payout_       The payout amount
    /// @param  prefunded_    Whether the lot was prefunded
    /// @param  callbackData_ Additional data for the callback
    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual;

    /// @inheritdoc ICallback
    function onBid(
        uint96 lotId_,
        uint64 bidId,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        _onBid(lotId_, bidId, buyer_, amount_, callbackData_);

        return this.onBid.selector;
    }

    /// @notice Implementation-specifc logic for the onBid callback
    /// @dev    This function should be overridden by the inheriting contract to implement custom logic. It is called at the end of the `onBid()` callback function.
    ///
    /// @param  lotId_        The lot ID
    /// @param  bidId         The bid ID
    /// @param  buyer_        The buyer submitting the bid
    /// @param  amount_       The bid amount
    /// @param  callbackData_ Additional data for the callback
    function _onBid(
        uint96 lotId_,
        uint64 bidId,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual;

    /// @inheritdoc ICallback
    function onSettle(
        uint96 lotId_,
        uint256 proceeds_,
        uint256 refund_,
        bytes calldata callbackData_
    ) external override onlyAuctionHouse onlyRegisteredLot(lotId_) returns (bytes4) {
        // Call implementation specific logic
        _onSettle(lotId_, proceeds_, refund_, callbackData_);

        return this.onSettle.selector;
    }

    /// @notice Implementation-specifc logic for the onSettle callback
    /// @dev    This function should be overridden by the inheriting contract to implement custom logic. It is called at the end of the `onSettle()` callback function.
    ///
    /// @param  lotId_        The lot ID
    /// @param  proceeds_     The proceeds from the sale
    /// @param  refund_       The refund amount
    /// @param  callbackData_ Additional data for the callback
    function _onSettle(
        uint96 lotId_,
        uint256 proceeds_,
        uint256 refund_,
        bytes calldata callbackData_
    ) internal virtual;
}
