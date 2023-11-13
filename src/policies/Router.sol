/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

import "src/Kernel.sol";
import {HOUSEv1} from "src/modules/HOUSE/HOUSE.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {VAULTv1} from "src/modules/VAULT/VAULT.v1.sol";

interface IRouter {

    struct Order {
        uint256 lotId;
        address user;
        address recipient;
        address referrer;
        uint256 amount;
        uint256 minAmountOut;
        uint256 maxFee;
        uint256 submitted;
        uint256 deadline;
    }

    enum Status {
        Open,
        Executed,
        Cancelled
    }

    // ========== DIRECT EXECUTION ========== //

    /// @notice Purchase directly from a live auction lot.
    function purchase(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_) external returns (uint256 payout);

    /// @notice Place a bid on an auction. Used for auction types that don't allow instant purchases.
    function bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_) external;

    function settle(uint256 id_) external;

    // ========== DELEGATED EXECUTION ========== //

    function executeOrder(Order calldata order_, bytes calldata signature_, uint256 fee_) external;

    function executeOrders(Order[] calldata orders_, bytes[] calldata signatures_, uint256[] calldata fees_) external;

    // TODO how to handle placing bids or purchases on multiple auctions at once?
    // TODO how to allow executor to place bids and then settle an auction?

    function orderDigest(Order calldata order_) external view returns (bytes32);

    function cancelOrder(Order calldata order_) external;

    function reinstateOrder(Order calldata order_) external;
    
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function updateDomainSeparator() external;

}

contract Router is IRouter, Policy, EIP712 {
    using SafeTransferLib for ERC20;

    // ========== EVENTS ========== //

    // ========== ERRORS ========== //

    // ========== STATE VARIABLES ========== //

    

    // Modules
    HOUSEv1 internal HOUSE;
    TRSRYv1 internal TRSRY;
    VAULTv1 internal VAULT;

    // ========== POLICY SETUP ========== //

    constructor(Kernel kernel_) Policy(kernel_) EIP712() {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("HOUSE");
        dependencies[1] = toKeycode("TRSRY");
        dependencies[2] = toKeycode("VAULT");

        // Cache modules
        HOUSE = HOUSEv1(getModuleForKeycode(dependencies[0]));
        TRSRY = TRSRYv1(getModuleForKeycode(dependencies[1]));
        VAULT = VAULTv1(getModuleForKeycode(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode HOUSE_KEYCODE = toKeycode("HOUSE");

        requests = new Permissions[](3);
        requests[0] = Permissions(HOUSE_KEYCODE, HOUSE.purchase.selector);
        requests[1] = Permissions(HOUSE_KEYCODE, HOUSE.bid.selector);
        requests[2] = Permissions(HOUSE_KEYCODE, HOUSE.settle.selector);
    }

    // ========== DIRECT EXECUTION ========== //

    /// @inheritdoc IRouter
    function purchase(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_) external override returns (uint256 payout) {
        // Calculate fees?
        uint256 fees;

        // Send purchase to auction house and get payout
        payout = HOUSE.purchase(id_, amount_, minAmountOut_);

        // Handle transfers from purchaser and seller
        _handleTransfers(id_, amount_, payout, fees);

        // Handle payout to user, including creation of derivative tokens
        _handlePayout(recipient_, id_, payout);

    }

    /// @inheritdoc IRouter
    function bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_) external override {
        // Calculate fees?
        uint256 fees;

        // Send bid to auction house
        HOUSE.bid(id_, amount_, minAmountOut_);

        // 
    }

    /// @notice     Handles transfer of funds from user and market owner/callback
    function _handleTransfers(
        uint256 id_,
        uint256 amount_,
        uint256 payout_,
        uint256 feePaid_
    ) internal {
        // Get info from auctioneer
        (address owner, address callbackAddr, ERC20 payoutToken, ERC20 quoteToken, , ) = _aggregator
            .getAuctioneer(id_)
            .getMarketInfoForPurchase(id_);

        // Calculate amount net of fees
        uint256 amountLessFee = amount_ - feePaid_;

        // Have to transfer to teller first since fee is in quote token
        // Check balance before and after to ensure full amount received, revert if not
        // Handles edge cases like fee-on-transfer tokens (which are not supported)
        uint256 quoteBalance = quoteToken.balanceOf(address(this));
        quoteToken.safeTransferFrom(msg.sender, address(this), amount_);
        if (quoteToken.balanceOf(address(this)) < quoteBalance + amount_)
            revert Teller_UnsupportedToken();

        // If callback address supplied, transfer tokens from teller to callback, then execute callback function,
        // and ensure proper amount of tokens transferred in.
        if (callbackAddr != address(0)) {
            // Send quote token to callback (transferred in first to allow use during callback)
            quoteToken.safeTransfer(callbackAddr, amountLessFee);

            // Call the callback function to receive payout tokens for payout
            uint256 payoutBalance = payoutToken.balanceOf(address(this));
            IBondCallback(callbackAddr).callback(id_, amountLessFee, payout_);

            // Check to ensure that the callback sent the requested amount of payout tokens back to the teller
            if (payoutToken.balanceOf(address(this)) < (payoutBalance + payout_))
                revert Teller_InvalidCallback();
        } else {
            // If no callback is provided, transfer tokens from market owner to this contract
            // for payout.
            // Check balance before and after to ensure full amount received, revert if not
            // Handles edge cases like fee-on-transfer tokens (which are not supported)
            uint256 payoutBalance = payoutToken.balanceOf(address(this));
            payoutToken.safeTransferFrom(owner, address(this), payout_);
            if (payoutToken.balanceOf(address(this)) < (payoutBalance + payout_))
                revert Teller_UnsupportedToken();

            quoteToken.safeTransfer(owner, amountLessFee);
        }
    }


}