// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {EmpaTest} from "test/EMPA/EMPATest.sol";

contract EmpaSetProtocolTest is EmpaTest {
    address internal immutable _NEW_PROTOCOL = address(0x7);

    uint96 internal constant _AMOUNT_IN = 1e18;
    uint96 internal _amountInProtocolFee = _AMOUNT_IN * _PROTOCOL_FEE_PERCENT / 1e5;

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
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenProtocolAddressIsSet(_NEW_PROTOCOL)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_AMOUNT_IN, 1e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
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
