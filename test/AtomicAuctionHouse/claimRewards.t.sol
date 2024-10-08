// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AtomicAuctionHouseTest} from "./AuctionHouseTest.sol";

contract AtomicClaimRewardsTest is AtomicAuctionHouseTest {
    uint256 internal constant _AMOUNT_IN = 1e18;
    uint256 internal _amountInReferrerFee = (_AMOUNT_IN * _REFERRER_FEE_PERCENT) / 100e2;
    uint256 internal _amountInProtocolFee = (_AMOUNT_IN * _PROTOCOL_FEE_PERCENT) / 100e2;
    uint256 internal _amountInLessFee = _AMOUNT_IN - _amountInReferrerFee - _amountInProtocolFee;
    // 1:1 exchange rate
    uint256 internal _amountOut = _amountInLessFee;

    bytes internal _purchaseAuctionData = abi.encode("");

    // ===== Modifiers ===== //

    // ===== Tests ===== //

    // [X] caller is _PROTOCOL
    // [X] caller is _REFERRER
    // [X] caller is another user

    // Note: the claimRewards functionality is shared between the Atomic and Batch AuctionHouses, so there is no need currently to have separate tests for each.

    function test_protocol()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenPurchase(_AMOUNT_IN, _amountInLessFee, _purchaseAuctionData)
    {
        // Previous balance
        uint256 previousBalance = _quoteToken.balanceOf(_PROTOCOL);

        // Claim rewards
        vm.prank(_PROTOCOL);
        _auctionHouse.claimRewards(address(_quoteToken));

        // Check new balance
        assertEq(_quoteToken.balanceOf(_PROTOCOL), previousBalance + _amountInProtocolFee);

        // Check rewards
        assertEq(_auctionHouse.rewards(_PROTOCOL, _quoteToken), 0);
    }

    function test_referrer()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenPurchase(_AMOUNT_IN, _amountInLessFee, _purchaseAuctionData)
    {
        // Previous balance
        uint256 previousBalance = _quoteToken.balanceOf(_REFERRER);

        // Claim rewards
        vm.prank(_REFERRER);
        _auctionHouse.claimRewards(address(_quoteToken));

        // Check new balance
        assertEq(_quoteToken.balanceOf(_REFERRER), previousBalance + _amountInReferrerFee);

        // Check rewards
        assertEq(_auctionHouse.rewards(_REFERRER, _quoteToken), 0);
    }

    function test_another_user()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenPurchase(_AMOUNT_IN, _amountInLessFee, _purchaseAuctionData)
    {
        // Previous balance
        uint256 previousBalance = _quoteToken.balanceOf(_bidder);

        // Claim rewards
        vm.prank(_bidder);
        _auctionHouse.claimRewards(address(_quoteToken));

        // Check new balance
        assertEq(_quoteToken.balanceOf(_bidder), previousBalance);

        // Check rewards
        assertEq(_auctionHouse.rewards(_bidder, _quoteToken), 0);
    }

    function test_anotherToken()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenPurchase(_AMOUNT_IN, _amountInLessFee, _purchaseAuctionData)
    {
        // Previous balance
        uint256 previousBalance = _baseToken.balanceOf(_PROTOCOL);

        // Claim rewards
        vm.prank(_PROTOCOL);
        _auctionHouse.claimRewards(address(_baseToken));

        // Check new balance
        assertEq(_baseToken.balanceOf(_PROTOCOL), previousBalance);

        // Check rewards
        assertEq(_auctionHouse.rewards(_PROTOCOL, _baseToken), 0);
    }
}
