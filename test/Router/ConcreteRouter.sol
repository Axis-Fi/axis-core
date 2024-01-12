/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

// Standard libraries
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Router} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

contract ConcreteRouter is Router {
    constructor(address protocol_) Router(protocol_) {}

    function purchase(PurchaseParams memory params_)
        external
        virtual
        override
        returns (uint256 payout)
    {}

    function bid(
        address recipient_,
        address referrer_,
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_,
        bytes calldata auctionData_,
        bytes calldata approval_
    ) external virtual override {}

    function settle(uint256 id_) external virtual override returns (uint256[] memory amountsOut) {}

    function settle(
        uint256 id_,
        Auction.Bid[] memory bids_
    ) external virtual override returns (uint256[] memory amountsOut) {}

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
}
