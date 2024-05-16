// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {Keycode} from "src/modules/Keycode.sol";

/// @title      IFeeManager
/// @notice     Defines the interface to interact with auction fees
interface IFeeManager {
    // ========== ERRORS ========== //

    error InvalidFee();

    // ========== DATA STRUCTURES ========== //

    /// @notice     Collection of fees charged for a specific auction type in basis points (3 decimals).
    /// @notice     Protocol and referrer fees are taken in the quoteToken and accumulate in the contract. These are set by the protocol.
    /// @notice     Curator fees are taken in the payoutToken and are sent when the auction is settled / purchase is made. Curators can set these up to the configured maximum.
    /// @dev        There are some situations where the fees may round down to zero if quantity of baseToken
    ///             is < 1e5 wei (can happen with big price differences on small decimal tokens). This is purely
    ///             a theoretical edge case, as the amount would not be practical.
    ///
    /// @param      protocol        Fee charged by the protocol
    /// @param      referrer        Fee charged by the referrer
    /// @param      maxCuratorFee   Maximum fee that a curator can charge
    /// @param      curator         Fee charged by a specific curator
    struct Fees {
        uint48 protocol;
        uint48 referrer;
        uint48 maxCuratorFee;
        mapping(address => uint48) curator;
    }

    /// @notice     Defines the type of fee to set
    enum FeeType {
        Protocol,
        Referrer,
        MaxCurator
    }

    // ========== FEE CALCULATIONS ========== //

    /// @notice     Calculates and allocates fees that are collected in the quote token
    ///
    /// @param      protocolFee_  Fee charged by the protocol
    /// @param      referrerFee_  Fee charged by the referrer
    /// @param      hasReferrer_  Whether the auction has a referrer
    /// @param      amount_       Amount to calculate fees for
    /// @return     toReferrer    Amount to send to the referrer
    /// @return     toProtocol    Amount to send to the protocol
    function calculateQuoteFees(
        uint48 protocolFee_,
        uint48 referrerFee_,
        bool hasReferrer_,
        uint256 amount_
    ) external view returns (uint256 toReferrer, uint256 toProtocol);

    // ========== FEE MANAGEMENT ========== //

    /// @notice     Sets the fee for a curator (the sender) for a specific auction type
    ///
    /// @param      auctionType_ Auction type to set fees for
    /// @param      fee_         Fee to charge
    function setCuratorFee(Keycode auctionType_, uint48 fee_) external;

    /// @notice     Gets the fees for a specific auction type
    ///
    /// @param      auctionType_  Auction type to get fees for
    /// @return     protocol      Fee charged by the protocol
    /// @return     referrer      Fee charged by the referrer
    /// @return     maxCuratorFee Maximum fee that a curator can charge
    function getFees(Keycode auctionType_)
        external
        view
        returns (uint48 protocol, uint48 referrer, uint48 maxCuratorFee);

    /// @notice     Gets the fee for a specific auction type and curator
    ///
    /// @param      auctionType_  Auction type to get fees for
    /// @param      curator_      Curator to get fees for
    /// @return     curatorFee    Fee charged by the curator
    function getCuratorFee(
        Keycode auctionType_,
        address curator_
    ) external view returns (uint48 curatorFee);

    // ========== REWARDS ========== //

    /// @notice     Claims the rewards for a specific token and the sender
    ///
    /// @param      token_  Token to claim rewards for
    function claimRewards(address token_) external;

    /// @notice     Gets the rewards for a specific recipient and token
    ///
    /// @param      recipient_  Recipient to get rewards for
    /// @param      token_      Token to get rewards for
    /// @return     reward      Reward amount
    function getRewards(
        address recipient_,
        address token_
    ) external view returns (uint256 reward);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice     Sets the protocol fee, referrer fee, or max curator fee for a specific auction type
    /// @notice     Access controlled: only owner
    ///
    /// @param      auctionType_  Auction type to set fees for
    /// @param      type_         Type of fee to set
    /// @param      fee_          Fee to charge
    function setFee(Keycode auctionType_, FeeType type_, uint48 fee_) external;

    /// @notice     Sets the protocol address
    /// @dev        Access controlled: only owner
    ///
    /// @param      protocol_  Address of the protocol
    function setProtocol(address protocol_) external;

    /// @notice     Gets the protocol address
    function getProtocol() external view returns (address);
}
