// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >= 0.8.19;

interface IAuctionModule {
    // ========== ERRORS ========== //

    error Auction_MarketNotActive(uint96 lotId);
    error Auction_MarketActive(uint96 lotId);
    error Auction_InvalidStart(uint48 start_, uint48 minimum_);
    error Auction_InvalidDuration(uint48 duration_, uint48 minimum_);
    error Auction_InvalidLotId(uint96 lotId);
    error Auction_OnlyMarketOwner();
    error Auction_AmountLessThanMinimum();
    error Auction_InvalidParams();
    error Auction_NotAuthorized();
    error Auction_NotImplemented();
    error Auction_InsufficientCapacity();

    // ========== DATA STRUCTURES ========== //

    /// @notice     Types of auctions
    enum AuctionType {
        Atomic,
        Batch
    }

    /// @notice     Parameters when creating an auction lot
    ///
    /// @param      start           The timestamp when the auction starts
    /// @param      duration        The duration of the auction (in seconds)
    /// @param      capacityInQuote Whether or not the capacity is in quote tokens
    /// @param      capacity        The capacity of the lot
    /// @param      implParams      Abi-encoded implementation-specific parameters
    struct AuctionParams {
        uint48 start;
        uint48 duration;
        bool capacityInQuote;
        uint256 capacity;
        bytes implParams;
    }

    /// @notice     Core data for an auction lot
    ///
    /// @param      start               The timestamp when the auction starts
    /// @param      conclusion          The timestamp when the auction ends
    /// @param      quoteTokenDecimals  The quote token decimals
    /// @param      baseTokenDecimals   The base token decimals
    /// @param      capacityInQuote     Whether or not the capacity is in quote tokens
    /// @param      capacity            The capacity of the lot
    /// @param      sold                The amount of base tokens sold
    /// @param      purchased           The amount of quote tokens purchased
    struct Lot {
        uint48 start; // 6 +
        uint48 conclusion; //
        uint8 quoteTokenDecimals;
        uint8 baseTokenDecimals;
        bool capacityInQuote;
        uint256 capacity;
        uint256 sold;
        uint256 purchased;
    }

    // ========== AUCTION MANAGEMENT ========== //

    /// @notice     Create an auction lot
    /// @dev        The implementing function should handle the following:
    ///             - Validate the lot parameters
    ///             - Store the lot data
    ///
    /// @param      lotId_                  The lot id
    /// @param      params_                 The auction parameters
    /// @param      quoteTokenDecimals_     The quote token decimals
    /// @param      baseTokenDecimals_      The base token decimals
    function auction(
        uint96 lotId_,
        AuctionParams memory params_,
        uint8 quoteTokenDecimals_,
        uint8 baseTokenDecimals_
    ) external;

    /// @notice     Cancel an auction lot
    /// @dev        The implementing function should handle the following:
    ///             - Validate the lot parameters
    ///             - Update the lot data
    ///
    /// @param      lotId_              The lot id
    function cancelAuction(uint96 lotId_) external;

    // ========== AUCTION INFORMATION ========== //

    /// @notice     Returns whether the auction is currently accepting bids or purchases
    /// @dev        The implementing function should handle the following:
    ///             - Return true if the lot is accepting bids/purchases
    ///             - Return false if the lot has ended, been cancelled, or not started yet
    ///
    /// @param      lotId_  The lot id
    /// @return     bool    Whether or not the lot is active
    function isLive(uint96 lotId_) external view returns (bool);

    /// @notice     Returns whether the auction has ended
    /// @dev        The implementing function should handle the following:
    ///             - Return true if the lot is not accepting bids/purchases and will not at any point
    ///             - Return false if the lot hasn't started or is actively accepting bids/purchases
    ///
    /// @param      lotId_  The lot id
    /// @return     bool    Whether or not the lot is active
    function hasEnded(uint96 lotId_) external view returns (bool);

    /// @notice     Get the remaining capacity of a lot
    /// @dev        The implementing function should handle the following:
    ///             - Return the remaining capacity of the lot
    ///
    /// @param      lotId_  The lot id
    /// @return     uint96 The remaining capacity of the lot
    function remainingCapacity(uint96 lotId_) external view returns (uint256);

    /// @notice     Get whether or not the capacity is in quote tokens
    /// @dev        The implementing function should handle the following:
    ///             - Return true if the capacity is in quote tokens
    ///             - Return false if the capacity is in base tokens
    ///
    /// @param      lotId_  The lot id
    /// @return     bool    Whether or not the capacity is in quote tokens
    function capacityInQuote(uint96 lotId_) external view returns (bool);

    /// @notice     Get the lot data for a given lot ID
    ///
    /// @param     lotId_  The lot ID
    function getLot(uint96 lotId_) external view returns (Lot memory);

    /// @notice     Get the auction type
    function auctionType() external view returns (AuctionType);
}
