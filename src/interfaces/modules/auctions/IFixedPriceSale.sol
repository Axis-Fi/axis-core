// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

/// @notice Interface for fixed price sale (atomic) auctions
/// @dev    This contract does not inherit from `IAtomicAuction` or `AtomicAuctionModule` in order to avoid conflicts. Implementing contracts should inherit from both `AtomicAuctionModule` and this interface.
interface IFixedPriceSale {
    // ========== ERRORS ========== //

    error Auction_InsufficientPayout();
    error Auction_PayoutGreaterThanMax();

    // ========== DATA STRUCTURES ========== //

    /// @notice                     Parameters for a fixed price auction
    ///
    /// @param price                The fixed price of the lot
    /// @param maxPayoutPercent     The maximum payout per purchase, as a percentage of the capacity (100% = 1e5)
    struct AuctionDataParams {
        uint256 price;
        uint24 maxPayoutPercent;
    }

    /// @notice     Parameters to the purchase function
    ///
    /// @param      minAmountOut    The minimum amount of the base token that must be received
    struct PurchaseParams {
        uint256 minAmountOut;
    }

    /// @notice             Auction-specific data for a lot
    ///
    /// @param price        The fixed price of the lot
    /// @param maxPayout    The maximum payout per purchase, in terms of the base token
    struct AuctionData {
        uint256 price;
        uint256 maxPayout;
    }
}
