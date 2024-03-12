// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract SetProtocolTest is AuctionHouseTest {
    address internal immutable _NEW_PROTOCOL = address(0x7);

    uint96 internal constant _AMOUNT_IN = 1e18;
    uint96 internal _amountInReferrerFee = _AMOUNT_IN * _REFERRER_FEE_PERCENT / 1e5;
    uint96 internal _amountInProtocolFee = _AMOUNT_IN * _PROTOCOL_FEE_PERCENT / 1e5;
    uint96 internal _amountInLessFee = _AMOUNT_IN - _amountInReferrerFee - _amountInProtocolFee;
    // 1:1 exchange rate
    uint96 internal _amountOut = _amountInLessFee;

    bytes internal _auctionDataParams = abi.encode("");

    // ===== Modifiers ===== //

    modifier givenProtocolAddressIsSet(address protocol_) {
        _auctionHouse.setProtocol(protocol_);
        _;
    }

    // ===== Tests ===== //

    // [X] when caller is not the owner
    //  [X] it reverts
    // [X] it sets the protocol address

    function test_unauthorized() public {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Call
        vm.prank(_bidder);
        _auctionHouse.setProtocol(_NEW_PROTOCOL);
    }

    function test_whenAddressIsNew()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolAddressIsSet(_NEW_PROTOCOL)
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        givenPurchase(_AMOUNT_IN, _amountOut, _auctionDataParams)
    {
        // Previous balance
        uint256 previousBalance = _quoteToken.balanceOf(_NEW_PROTOCOL);

        // Claim rewards
        // As the protocol address is private, we cannot check that it was changed. But we can check that rewards were accrued.
        vm.prank(_NEW_PROTOCOL);
        _auctionHouse.claimRewards(address(_quoteToken));

        // Check new balance
        assertEq(_quoteToken.balanceOf(_NEW_PROTOCOL), previousBalance + _amountInProtocolFee);

        // Check rewards
        assertEq(_auctionHouse.rewards(_NEW_PROTOCOL, _quoteToken), 0);
    }
}
