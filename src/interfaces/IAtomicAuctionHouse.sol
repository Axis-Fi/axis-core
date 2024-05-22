// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";

/// @title      IAtomicAuctionHouse
/// @notice     An interface to define the AtomicAuctionHouse's buyer-facing functions
interface IAtomicAuctionHouse is IAuctionHouse {
    // ========== DATA STRUCTURES ========== //

    /// @notice     Parameters used by the purchase function
    /// @dev        This reduces the number of variables in scope for the purchase function
    ///
    /// @param      recipient           Address to receive payout (if not zero address)
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
    ) external returns (uint256 payout);

    /// @notice     Purchase from multiple lots in a single transaction
    /// @notice     Permit2 is utilised to simplify token transfers
    ///
    /// @param      params_         Array of purchase parameters
    /// @param      callbackData_   Array of custom data provided to the onPurchase callbacks
    /// @return     payouts         Array of amounts of baseTokens received by `recipient_` (in native decimals)
    function multiPurchase(
        PurchaseParams[] memory params_,
        bytes[] calldata callbackData_
    ) external returns (uint256[] memory payouts);
}
