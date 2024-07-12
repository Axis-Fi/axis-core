// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineTokenAllowlistTest} from
    "test/callbacks/liquidity/BaselineV2/TokenAllowlist/BaselineTokenAllowlistTest.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

contract BaselineTokenAllowlistOnBidTest is BaselineTokenAllowlistTest {
    uint64 internal constant _BID_ID = 1;

    // ========== MODIFIER ========== //

    function _onBid(uint256 bidAmount_) internal {
        // Call the callback
        vm.prank(address(_auctionHouse));
        _dtl.onBid(_lotId, _BID_ID, _BUYER, bidAmount_, abi.encode(""));
    }

    // ========== TESTS ========== //

    // [X] if the buyer has below the threshold
    //  [X] it reverts
    // [X] it succeeds

    function test_buyerBelowThreshold_reverts(
        uint256 bidAmount_,
        uint256 tokenBalance_
    )
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenTokenIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(address(_token), _TOKEN_THRESHOLD)
        givenOnCreate
    {
        uint256 bidAmount = bound(bidAmount_, 1, 10e18);
        uint256 tokenBalance = bound(tokenBalance_, 0, _TOKEN_THRESHOLD - 1);

        // Mint the token balance
        _token.mint(_BUYER, tokenBalance);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        _onBid(bidAmount);
    }

    function test_success(
        uint256 bidAmount_,
        uint256 tokenBalance_
    )
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenTokenIsCreated
        givenAuctionIsCreated
        givenAllowlistParams(address(_token), _TOKEN_THRESHOLD)
        givenOnCreate
    {
        uint256 bidAmount = bound(bidAmount_, 1, 10e18);
        uint256 tokenBalance = bound(tokenBalance_, _TOKEN_THRESHOLD, _TOKEN_THRESHOLD * 2);

        // Mint the token balance
        _token.mint(_BUYER, tokenBalance);

        // Call the callback
        _onBid(bidAmount);
    }
}
