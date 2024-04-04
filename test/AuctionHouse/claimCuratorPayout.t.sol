// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract ClaimCuratorPayoutTest is AuctionHouseTest {
    uint96 internal constant _BID_AMOUNT = 2e18;
    uint96 internal constant _BID_AMOUNT_OUT = 2e18;

    uint96 internal constant _BID_AMOUNT_PARTIAL_REFUND = 15e17;
    uint96 internal constant _BID_AMOUNT_OUT_PARTIAL_PAYOUT = 1e18;

    // ============ Assertions ============ //

    function _assertBaseTokenBalances(
        uint256 unusedCapacity,
        uint256 claimableBids,
        uint256 claimableCuratorPayout
    ) internal {
        bool isLotProceedsClaimed = _batchAuctionModule.lotProceedsClaimed(_lotId);

        assertEq(
            _baseToken.balanceOf(_SELLER),
            isLotProceedsClaimed ? unusedCapacity : 0,
            "base token: seller"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            (isLotProceedsClaimed ? 0 : unusedCapacity) + claimableBids,
            "base token: auction house"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), claimableCuratorPayout, "base token: curator");

        // Check the lot
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            lotRouting.funding,
            (isLotProceedsClaimed ? 0 : unusedCapacity) + claimableBids,
            "funding"
        );
    }

    // ============ Modifiers ============ //

    modifier givenLotSettlementIsSuccessful() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            Auction.Settlement({
                totalIn: _scaleQuoteTokenAmount(_BID_AMOUNT),
                totalOut: _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
                auctionOutput: ""
            })
        );

        _auctionHouse.settle(_lotId);
        _;
    }

    // ===== Tests ===== //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction has not concluded
    //  [X] it reverts
    // [X] when the auction has not been settled
    //  [X] it reverts
    // [ ] when the auction module reverts
    //  [ ] it reverts
    // [X] given the curator payout has already been claimed
    //  [X] it reverts
    // [X] given the lot is not curated
    //  [X] it reverts
    // [ ] given the capacity is not filled
    //  [ ] it calculates the curator payout based on the utilised capacity
    // [ ] given the seller has claimed proceeds
    //  [ ] given the bidders have claimed proceeds
    //   [ ] it calculates the curator payout based on the utilised capacity
    //  [ ] it calculates the curator payout based on the utilised capacity
    // [ ] given the bidders have claimed proceeds
    //  [ ] it calculates the curator payout based on the utilised capacity
    // [ ] when the caller is not the curator
    //  [ ] it transfers to the curator

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);
    }

    function test_lotNotConcluded_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);
    }

    function test_lotNotSettled_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);
    }

    function test_givenAlreadyClaimed_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
        givenCuratorPayoutIsClaimed
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);
    }

    function test_givenCuratorNotApproved()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
        givenCuratorPayoutIsClaimed
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);
    }

    function test_lotSettlementSuccessful()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 claimableBids = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual =
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT) * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _curatorMaxPotentialFee - claimableBids;

        // Assert balances
        _assertBaseTokenBalances(unusedCapacity, claimableBids, curatorFeeActual);
    }
}
