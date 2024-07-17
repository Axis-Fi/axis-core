// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IFeeManager} from "../interfaces/IFeeManager.sol";

// Internal libraries
import {Transfer} from "../lib/Transfer.sol";

// External libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solmate-6.7.0/utils/ReentrancyGuard.sol";
import {FixedPointMathLib as Math} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";

import {Keycode} from "../modules/Keycode.sol";

/// @title      FeeManager
/// @notice     Defines fees for auctions and manages the collection and distribution of fees
abstract contract FeeManager is IFeeManager, ReentrancyGuard {
    // ========== STATE VARIABLES ========== //

    /// @notice     Fees are in basis points (hundredths of a percent). 1% equals 100.
    uint48 internal constant _FEE_DECIMALS = 100e2;

    /// @notice     Address the protocol receives fees at
    address internal _protocol;

    /// @notice     Fees charged for each auction type
    /// @dev        See Fees struct for more details
    mapping(Keycode => Fees) public fees;

    /// @notice     Fees earned by an address, by token
    mapping(address => mapping(ERC20 => uint256)) public rewards;

    // ========== CONSTRUCTOR ========== //

    constructor(address protocol_) {
        _protocol = protocol_;
    }

    // ========== FEE CALCULATIONS ========== //

    /// @inheritdoc IFeeManager
    function calculateQuoteFees(
        uint48 protocolFee_,
        uint48 referrerFee_,
        bool hasReferrer_,
        uint256 amount_
    ) public pure returns (uint256 toReferrer, uint256 toProtocol) {
        if (hasReferrer_) {
            // In this case we need to:
            // 1. Calculate referrer fee
            // 2. Calculate protocol fee as the total expected fee amount minus the referrer fee
            //    to avoid issues with rounding from separate fee calculations
            toReferrer = Math.mulDivDown(amount_, referrerFee_, _FEE_DECIMALS);
            toProtocol =
                Math.mulDivDown(amount_, protocolFee_ + referrerFee_, _FEE_DECIMALS) - toReferrer;
        } else {
            // If there is no referrer, the protocol gets the entire fee
            toProtocol = Math.mulDivDown(amount_, protocolFee_ + referrerFee_, _FEE_DECIMALS);
        }
    }

    /// @notice     Calculates and allocates fees that are collected in the payout token
    function _calculatePayoutFees(
        bool curated_,
        uint48 curatorFee_,
        uint256 payout_
    ) internal pure returns (uint256 toCurator) {
        // No fees if the auction is not yet curated
        if (curated_ == false) return 0;

        // Calculate curator fee
        toCurator = Math.mulDivDown(payout_, uint256(curatorFee_), uint256(_FEE_DECIMALS));
    }

    // ========== FEE MANAGEMENT ========== //

    /// @inheritdoc IFeeManager
    function setCuratorFee(Keycode auctionType_, uint48 fee_) external {
        // Check that the fee is less than the maximum
        if (fee_ > fees[auctionType_].maxCuratorFee) revert InvalidFee();

        // Set the fee for the sender
        fees[auctionType_].curator[msg.sender] = fee_;
    }

    /// @inheritdoc IFeeManager
    function getFees(Keycode auctionType_)
        external
        view
        override
        returns (uint48 protocol, uint48 maxReferrerFee, uint48 maxCuratorFee)
    {
        Fees storage fee = fees[auctionType_];
        return (fee.protocol, fee.maxReferrerFee, fee.maxCuratorFee);
    }

    /// @inheritdoc IFeeManager
    function getCuratorFee(
        Keycode auctionType_,
        address curator_
    ) external view override returns (uint48 curatorFee) {
        return fees[auctionType_].curator[curator_];
    }

    // ========== REWARDS ========== //

    /// @inheritdoc IFeeManager
    /// @dev        This function reverts if:
    ///             - re-entrancy is detected
    function claimRewards(address token_) external nonReentrant {
        ERC20 token = ERC20(token_);
        uint256 amount = rewards[msg.sender][token];
        rewards[msg.sender][token] = 0;

        Transfer.transfer(token, msg.sender, amount, false);
    }

    /// @inheritdoc IFeeManager
    function getRewards(
        address recipient_,
        address token_
    ) external view override returns (uint256 reward) {
        return rewards[recipient_][ERC20(token_)];
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IFeeManager
    function getProtocol() public view returns (address) {
        return _protocol;
    }
}
