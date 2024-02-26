// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract EmpaClaimRewardsTest is EmpaTest {
    // [X] given the caller has no rewards
    //  [X] 0 rewards are claimed
    // [X] when an untracked token is provided
    //  [X] 0 rewards are claimed
    // [X] when a tracked token is provided
    //  [X] rewards are claimed and the pending amount set to 0

    function test_givenNoRewards() public {
        uint256 balanceBefore = _quoteToken.balanceOf(_bidder);

        vm.prank(_bidder);
        _auctionHouse.claimRewards(address(_quoteToken));

        assertEq(_quoteToken.balanceOf(_bidder), balanceBefore);
    }

    function test_untrackedToken() external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenOwnerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenOwnerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotHasStarted
        givenBidIsCreated(1e18, 2e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        uint256 balanceBefore = _baseToken.balanceOf(_bidder);

        vm.prank(_PROTOCOL);
        _auctionHouse.claimRewards(address(_baseToken));

        assertEq(_baseToken.balanceOf(_bidder), balanceBefore);
    }

    function test_protocol() external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenOwnerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenOwnerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotHasStarted
        givenBidIsCreated(8e18, 4e18)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
        givenBidIsClaimed(1)
    {
        uint256 balanceBefore = _quoteToken.balanceOf(_PROTOCOL);
        uint256 expectedFee = FixedPointMathLib.mulDivDown(8e18, _PROTOCOL_FEE_PERCENT, 1e5);

        vm.prank(_PROTOCOL);
        _auctionHouse.claimRewards(address(_quoteToken));

        assertEq(_quoteToken.balanceOf(_PROTOCOL), balanceBefore + expectedFee);
    }
}
