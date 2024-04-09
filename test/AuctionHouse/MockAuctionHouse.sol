/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";

import {Auction} from "src/modules/Auction.sol";
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {ICallback} from "src/interfaces/ICallback.sol";

/// @notice     Mock AuctionHouse contract for testing
/// @dev        It currently exposes some internal functions so that they can be tested in isolation
contract MockAuctionHouse is AuctionHouse {
    constructor(
        address protocol_,
        address permit2_
    ) AuctionHouse(msg.sender, protocol_, permit2_) {}

    // Expose the _collectPayment function for testing
    function collectPayment(
        uint256 amount_,
        ERC20 quoteToken_,
        Transfer.Permit2Approval memory approval_
    ) external {
        return _collectPayment(amount_, quoteToken_, approval_);
    }

    function sendPayment(
        address lotOwner_,
        uint256 paymentAmount_,
        ERC20 quoteToken_,
        ICallback callbacks_
    ) external {
        return _sendPayment(lotOwner_, paymentAmount_, quoteToken_, callbacks_);
    }

    function sendPayout(
        address recipient_,
        uint256 payoutAmount_,
        AuctionHouse.Routing memory routingParams_,
        bytes memory auctionOutput_
    ) external {
        return _sendPayout(recipient_, payoutAmount_, routingParams_, auctionOutput_);
    }

    // Not implemented

    function _auction(
        uint96 lotId_,
        RoutingParams calldata routing_,
        Auction.AuctionParams calldata params_
    ) internal virtual override returns (bool performedCallback) {}

    function _cancel(
        uint96 lotId_,
        bytes calldata callbackData_
    ) internal virtual override returns (bool performedCallback) {}
}
