// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {FeeManager} from "src/EMPA.sol";

contract EmpaSetFeeTest is EmpaTest {
    address internal immutable newProtocol = address(0x7);

    uint24 internal constant _PROTOCOL_FEE_PERCENT = 100;

    uint96 internal constant _AMOUNT_IN = 1e18;
    uint96 internal _amountInProtocolFee = _AMOUNT_IN * _PROTOCOL_FEE_PERCENT / 1e5;

    // ===== Modifiers ===== //

    modifier givenProtocolAddressIsSet(address protocol_) {
        _auctionHouse.setProtocol(protocol_);
        _;
    }

    modifier givenProtocolFeeIsSet(uint24 fee_) {
        _auctionHouse.setFee(FeeManager.FeeType.Protocol, fee_);
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
        vm.prank(_BIDDER);
        _auctionHouse.setProtocol(newProtocol);
    }

    function test_whenAddressIsNew()
        public
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenProtocolAddressIsSet(newProtocol)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_AMOUNT_IN, 1e18)
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Previous balance
        uint256 previousBalance = _quoteToken.balanceOf(newProtocol);

        // Claim rewards
        // As the protocol address is private, we cannot check that it was changed. But we can check that rewards were accrued.
        vm.prank(newProtocol);
        _auctionHouse.claimRewards(address(_quoteToken));

        // Check new balance
        assertEq(_quoteToken.balanceOf(newProtocol), previousBalance + _amountInProtocolFee);

        // Check rewards
        assertEq(_auctionHouse.rewards(newProtocol, _quoteToken), 0);
    }
}
