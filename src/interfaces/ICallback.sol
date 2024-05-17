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
    ///     Bit 6: onSettle
    ///     Bit 7: Receives quote tokens
    ///     Bit 8: Sends base tokens (and receives them if refunded)

    // General functions that can be used by all auctions

    /// @notice Called when an auction is created. Reverts if validation fails.
    /// @dev    The implementing function should:
    ///         - Register the lot ID on the Callback contract
    ///         - Validate that the seller is allowed to use the Callback contract
    ///
    /// @param  lotId         The ID of the lot
    /// @param  seller        The address of the seller
    /// @param  baseToken     The address of the base token
    /// @param  quoteToken    The address of the quote token
    /// @param  capacity      The capacity of the auction
    /// @param  preFund       If true, the calling contract expects base tokens to be sent to it
    /// @param  callbackData  Custom data provided by the seller
    function onCreate(
        uint96 lotId,
        address seller,
        address baseToken,
        address quoteToken,
        uint256 capacity,
        bool preFund,
        bytes calldata callbackData
    ) external returns (bytes4);

    /// @notice Called when an auction is cancelled.
    /// @dev    If the Callback is configured to receive tokens and the auction was prefunded, then the refund will be sent prior to the call.
    ///
    /// @param  lotId           The ID of the lot
    /// @param  refund          The refund amount
    /// @param  preFunded       If true, the calling contract will have sent base tokens prior to the call
    /// @param  callbackData    Custom data provided by the seller
    function onCancel(
        uint96 lotId,
        uint256 refund,
        bool preFunded,
        bytes calldata callbackData
    ) external returns (bytes4);

    /// @notice Called when curate is called for an auction.
    ///
    /// @param  lotId         The ID of the lot
    /// @param  curatorFee    The curator fee payout
    /// @param  preFund       If true, the calling contract expects base tokens to be sent to it
    /// @param  callbackData  Custom data provided by the seller
    function onCurate(
        uint96 lotId,
        uint256 curatorFee,
        bool preFund,
        bytes calldata callbackData
    ) external returns (bytes4);

    // Atomic Auction hooks

    /// @notice Called when a buyer purchases from an atomic auction. Reverts if validation fails.
    /// @dev    If the Callback is configured to receive quote tokens, then the user purchase amount of quote tokens will be sent prior to this call.
    ///         If the Callback is configured to send base tokens, then the AuctionHouse will expect the payout of base tokens to be sent back.
    ///
    /// @param  lotId         The ID of the lot
    /// @param  buyer         The address of the buyer
    /// @param  amount        The amount of quote tokens purchased
    /// @param  payout        The amount of base tokens to receive
    /// @param  preFunded     If true, the calling contract has already been provided the base tokens. Otherwise, they must be provided.
    /// @param  callbackData  Custom data provided by the buyer
    function onPurchase(
        uint96 lotId,
        address buyer,
        uint256 amount,
        uint256 payout,
        bool preFunded,
        bytes calldata callbackData
    ) external returns (bytes4);

    // Batch Auction hooks

    /// @notice Called when a buyer bids on a batch auction. Reverts if validation fails.
    ///
    /// @param  lotId         The ID of the lot
    /// @param  bidId         The ID of the bid
    /// @param  buyer         The address of the buyer
    /// @param  amount        The amount of quote tokens bid
    /// @param  callbackData  Custom data provided by the buyer
    function onBid(
        uint96 lotId,
        uint64 bidId,
        address buyer,
        uint256 amount,
        bytes calldata callbackData
    ) external returns (bytes4);

    /// @notice Called when a batch auction is settled.
    /// @dev    If the Callback is configured to receive tokens, then the proceeds and/or refund will be sent prior to the call.
    ///
    /// @param  lotId         The ID of the lot
    /// @param  proceeds      The proceeds amount
    /// @param  refund        The refund amount
    /// @param  callbackData  Custom data provided by the seller
    function onSettle(
        uint96 lotId,
        uint256 proceeds,
        uint256 refund,
        bytes calldata callbackData
    ) external returns (bytes4);
}
