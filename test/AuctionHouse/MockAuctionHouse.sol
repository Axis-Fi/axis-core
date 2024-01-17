/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

import {Auctioneer} from "src/bases/Auctioneer.sol";

/// @notice     Mock AuctionHouse contract for testing
/// @dev        It currently exposes some internal functions so that they can be tested in isolation
contract MockAuctionHouse is AuctionHouse {
    constructor(address protocol_, address permit2_) AuctionHouse(protocol_, permit2_) {}

    // Expose the _collectPayment function for testing
    function collectPayment(
        uint256 lotId_,
        uint256 amount_,
        ERC20 quoteToken_,
        IHooks hooks_,
        uint48 approvalDeadline_,
        uint256 approvalNonce_,
        bytes memory approvalSignature_
    ) external {
        return _collectPayment(
            lotId_,
            amount_,
            quoteToken_,
            hooks_,
            approvalDeadline_,
            approvalNonce_,
            approvalSignature_
        );
    }

    function collectPayout(
        uint256 lotId_,
        uint256 paymentAmount_,
        uint256 payoutAmount_,
        Auctioneer.Routing memory routingParams_
    ) external {
        return _collectPayout(lotId_, paymentAmount_, payoutAmount_, routingParams_);
    }

    function sendPayment(
        address lotOwner_,
        uint256 paymentAmount_,
        ERC20 quoteToken_,
        IHooks hooks_
    ) external {
        return _sendPayment(lotOwner_, paymentAmount_, quoteToken_, hooks_);
    }

    function sendPayout(
        uint256 lotId_,
        address recipient_,
        uint256 payoutAmount_,
        ERC20 payoutToken_,
        IHooks hooks_
    ) external {
        return _sendPayout(lotId_, recipient_, payoutAmount_, payoutToken_, hooks_);
    }
}
