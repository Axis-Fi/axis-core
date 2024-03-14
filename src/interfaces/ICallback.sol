// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title  ICallback
/// @notice Interface for callback contracts use in the Axis system
interface ICallback {
    /// @notice Callback configuration. Used by AuctionHouse to know which functions are implemented on this contract.
    /// @dev 8-bit map of which callbacks are implemented on this contract.
    ///     The last two bits designate whether the callback should be expected send base tokens and receive quote tokens.
    ///     If the contract does not send/receive, then the AuctionHouse will expect the tokens to be sent/received directly by the seller wallet.
    ///     Bit 1: onCreate
    ///     Bit 2: onCancel
    ///     Bit 3: onCurate
    ///     Bit 4: onPurchase
    ///     Bit 5: onBid
    ///     Bit 6: onClaimProceeds
    ///     Bit 7: Receives quote tokens
    ///     Bit 8: Sends base tokens (and receives them if refunded)

    // General functions that can be used by all auctions

    /// @notice Called when an auction is created. Reverts if validation fails.
    /// @dev Should register the lot ID on the Callback contract and validate seller is allowed to use the Callback contract
    /// @dev If the Callback is configured to send tokens and the auction is to be prefunded, then the AuctionHouse will expect the capacity of base tokens to be sent back.
    function onCreate(
        uint96 lotId,
        address seller,
        address baseToken,
        address quoteToken,
        uint96 capacity,
        bool preFund,
        bytes calldata callbackData
    ) external returns (bytes4);

    /// @notice Called when an auction is cancelled.
    /// @dev If the Callback is configured to receive tokens and the auction was prefunded, then the refund will be sent prior to the call.
    function onCancel(
        uint96 lotId,
        uint96 refund,
        bool preFunded,
        bytes calldata callbackData
    ) external returns (bytes4);

    /// @notice Called when curate is called for an auction.
    /// @dev If the Callback is configured to send tokens and the auction is to be prefunded, then the AuctionHouse will expect the curatorFee of base tokens to be sent back.
    function onCurate(
        uint96 lotId,
        uint96 curatorFee,
        bool preFund,
        bytes calldata callbackData
    ) external returns (bytes4);

    // Atomic Auction hooks

    /// @notice Called when a buyer purchases from an atomic auction. Reverts if validation fails.
    /// @dev If the Callback is configured to receive tokens, then the user purchase amount of quote tokens will be sent prior to this call.
    /// @dev If the Callback is configured to send tokens and the auction wasn't prefunded, then the AuctionHouse will expect the payout of base tokens to be sent back.
    function onPurchase(
        uint96 lotId,
        address buyer,
        uint96 amount,
        uint96 payout,
        bool preFunded,
        bytes calldata callbackData
    ) external returns (bytes4);

    // Batch Auction hooks

    /// @notice Called when a buyer bids on a batch auction. Reverts if validation fails.
    function onBid(
        uint96 lotid,
        uint64 bidId,
        address buyer,
        uint96 amount,
        bytes calldata callbackData
    ) external returns (bytes4);

    /// @notice Called when the seller claims their proceeds from the auction.
    /// @dev If the Callback is configured to receive tokens, then the proceeds and/or refund will be sent prior to the call.
    function onClaimProceeds(
        uint96 lotId,
        uint96 proceeds,
        uint96 refund,
        bytes calldata callbackData
    ) external returns (bytes4);
}
