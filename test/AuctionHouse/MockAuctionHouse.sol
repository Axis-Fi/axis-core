/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

import {Auctioneer} from "src/bases/Auctioneer.sol";

/// @notice     Mock AuctionHouse contract for testing
/// @dev        It currently exposes some internal functions so that they can be tested in isolation
contract MockAuctionHouse is AuctionHouse {
    constructor(address protocol_, address permit2_) AuctionHouse(protocol_, permit2_) {}

    // Expose the _collectPayment function for testing
    function collectPayment(
        uint96 lotId_,
        uint256 amount_,
        ERC20 quoteToken_,
        IHooks hooks_,
        uint48 approvalDeadline_,
        uint256 approvalNonce_,
        bytes memory approvalSignature_
    ) external {
        Transfer.Permit2Approval memory approval = Transfer.Permit2Approval({
            deadline: approvalDeadline_,
            nonce: approvalNonce_,
            signature: approvalSignature_
        });

        return _collectPayment(lotId_, amount_, quoteToken_, hooks_, approval);
    }

    function sendPayment(
        address lotOwner_,
        uint256 paymentAmount_,
        ERC20 quoteToken_,
        IHooks hooks_
    ) external {
        return _sendPayment(lotOwner_, paymentAmount_, quoteToken_, hooks_);
    }

    function collectPayout(
        uint96 lotId_,
        uint256 paymentAmount_,
        uint256 payoutAmount_,
        Auctioneer.Routing memory routingParams_
    ) external {
        return _collectPayout(lotId_, paymentAmount_, payoutAmount_, routingParams_);
    }

    function sendPayout(
        uint96 lotId_,
        address recipient_,
        uint256 payoutAmount_,
        Auctioneer.Routing memory routingParams_,
        bytes memory auctionOutput_
    ) external {
        return _sendPayout(lotId_, recipient_, payoutAmount_, routingParams_, auctionOutput_);
    }
}
