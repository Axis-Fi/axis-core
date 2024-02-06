/// SPDX-License-Identifier: APGL-3.0
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";

import {Keycode} from "src/modules/Modules.sol";

/// @title      FeeManager
/// @notice     Defines fees for auctions and manages the collection and distribution of fees
abstract contract FeeManager is Owned {
    using SafeTransferLib for ERC20;

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

    enum FeeType {
        Protocol,
        Referrer,
        MaxCurator
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     Fees are in basis points (3 decimals). 1% equals 1000.
    uint48 internal constant _FEE_DECIMALS = 1e5;

    /// @notice     Address the protocol receives fees at
    address internal _protocol;

    /// @notice     Fees charged for each auction type
    /// @dev        See Fees struct for more details
    mapping(Keycode => Fees) public fees;

    /// @notice     Fees earned by an address, by token
    mapping(address => mapping(ERC20 => uint256)) public rewards;

    // ========== FEE CALCULATIONS ========== //

    /// @notice     Calculates and allocates fees that are collected in the quote token
    function calculateQuoteFees(
        Keycode auctionType_,
        bool hasReferrer_,
        uint256 amount_
    ) public view returns (uint256 toReferrer, uint256 toProtocol) {
        // Load protocol fee for the auction type
        uint48 protocolFee = fees[auctionType_].protocol;

        if (hasReferrer_) {
            // Load referrer fee for the auction type
            uint48 referrerFee = fees[auctionType_].referrer;

            // In this case we need to:
            // 1. Calculate referrer fee
            // 2. Calculate protocol fee as the total expected fee amount minus the referrer fee
            //    to avoid issues with rounding from separate fee calculations
            toReferrer = (amount_ * referrerFee) / _FEE_DECIMALS;
            toProtocol = ((amount_ * (protocolFee + referrerFee)) / _FEE_DECIMALS) - toReferrer;
        } else {
            // There is no referrer
            toProtocol = (amount_ * protocolFee) / _FEE_DECIMALS;
        }
    }

    /// @notice     Calculates and allocates fees that are collected in the payout token
    function _calculatePayoutFees(
        Keycode auctionType_,
        address curator_,
        uint256 payout_
    ) internal view returns (uint256 toCurator) {
        // Calculate curator fee
        toCurator = (payout_ * fees[auctionType_].curator[curator_]) / _FEE_DECIMALS;
    }

    /// @notice Estimates fees for a `priceFor` or `maxAmountAccepted` calls
    function calculateFeeEstimate(
        Keycode auctionType_,
        bool hasReferrer_,
        uint256 price_
    ) external view returns (uint256 feeEstimate) {
        // In this case we have to invert the fee calculation
        // We provide a conservative estimate by assuming there is a referrer and rounding up
        uint48 fee = fees[auctionType_].protocol;
        if (hasReferrer_) fee += fees[auctionType_].referrer;

        uint256 numer = price_ * _FEE_DECIMALS;
        uint256 denom = _FEE_DECIMALS - fee;

        return (numer / denom) + ((numer % denom == 0) ? 0 : 1); // round up if necessary
    }

    // ========== FEE MANAGEMENT ========== //

    /// @notice     Sets the protocol fee, referrer fee, or max curator fee for a specific auction type
    /// @notice     Access controlled: only owner
    function setFee(Keycode auctionType_, FeeType type_, uint48 fee_) external onlyOwner {
        // Check that the fee is a valid percentage
        if (fee_ > _FEE_DECIMALS) revert InvalidFee();

        // Set fee based on type
        // TODO should we have hard-coded maximums for these fees?
        // Or a combination of protocol and referrer fee since they are both in the quoteToken?
        if (type_ == FeeType.Protocol) {
            fees[auctionType_].protocol = fee_;
        } else if (type_ == FeeType.Referrer) {
            fees[auctionType_].referrer = fee_;
        } else if (type_ == FeeType.MaxCurator) {
            fees[auctionType_].maxCuratorFee = fee_;
        }
    }

    /// @notice     Sets the fee for a curator (the sender) for a specific auction type
    function setCuratorFee(Keycode auctionType_, uint48 fee_) external {
        // Check that the fee is less than the maximum
        if (fee_ > fees[auctionType_].maxCuratorFee) revert InvalidFee();

        // Set the fee for the sender
        fees[auctionType_].curator[msg.sender] = fee_;
    }

    /// @notice     Claims the rewards for a specific token and the sender
    ///
    /// @param      token_  Token to claim rewards for
    function claimRewards(address token_) external {
        ERC20 token = ERC20(token_);
        uint256 amount = rewards[msg.sender][token];
        rewards[msg.sender][token] = 0;

        token.safeTransfer(msg.sender, amount);
    }

    /// @notice     Sets the protocol address
    /// @dev        Access controlled: only owner
    ///
    /// @param      protocol_  Address of the protocol
    function setProtocol(address protocol_) external onlyOwner {
        _protocol = protocol_;
    }
}