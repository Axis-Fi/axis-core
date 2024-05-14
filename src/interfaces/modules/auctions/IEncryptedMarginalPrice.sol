// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {Point} from "src/lib/ECIES.sol";

/// @notice Interface for encrypted marginal price (batch) auctions
/// @dev    This contract does not inherit from `BatchAuctionModule` in order to avoid conflicts. Implementing contracts should inherit from both `BatchAuctionModule` and this interface.
interface IEncryptedMarginalPrice {
    /// @notice         Parameters that are used to set auction-specific data
    ///
    /// @param          minPrice            The minimum price (in quote tokens) that a bid must fulfill
    /// @param          minFillPercent      The minimum percentage of capacity that the lot must fill in order to settle. Maximum value = 100_000 = 1e5.
    /// @param          minBidSize          The minimum size of a bid in quote tokens
    /// @param          publicKey           The public key used to encrypt bids
    struct AuctionDataParams {
        uint256 minPrice;
        uint24 minFillPercent;
        uint256 minBidSize;
        Point publicKey;
    }

    /// @notice     Parameters to the bid function
    ///
    /// @param      encryptedAmountOut      The encrypted value of the bid amount out
    /// @param      bidPublicKey            The public key used to encrypt the bid
    struct BidParams {
        uint256 encryptedAmountOut;
        Point bidPublicKey;
    }
}
