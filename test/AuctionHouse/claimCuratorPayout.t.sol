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

    /// @dev    Assumes that any amounts are scaled to the current decimal scale
    modifier givenPayoutIsSet(
        uint64 bidId_,
        address bidder_,
        address referrer_,
        uint96 amountIn_,
        uint96 payout_
    ) {
        _batchAuctionModule.addBidClaim(_lotId, bidId_, bidder_, referrer_, amountIn_, payout_, 0);
        _;
    }

    // ===== Tests ===== //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction has not concluded
    //  [X] it reverts
    // [X] when the auction has not been settled
    //  [X] it reverts
    // [X] given the curator payout has already been claimed
    //  [X] it reverts
    // [X] given the lot is not curated
    //  [X] it reverts
    // [X] given the capacity is not filled
    //  [X] it calculates the curator payout based on the utilised capacity
    // [X] given the seller has claimed proceeds
    //  [X] given the bidders have claimed proceeds
    //   [X] it calculates the curator payout based on the utilised capacity
    //  [X] it calculates the curator payout based on the utilised capacity
    // [X] given the bidders have claimed proceeds
    //  [X] it calculates the curator payout based on the utilised capacity
    // [X] when the caller is not the curator
    //  [X] it transfers to the curator

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

    function test_givenCuratorNotApproved_reverts()
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
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);
    }

    function test_success()
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
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);

        uint256 claimableBids = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual =
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT) * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY) + _curatorMaxPotentialFee
            - claimableBids - curatorFeeActual;

        // Assert balances
        _assertBaseTokenBalances(unusedCapacity, claimableBids, curatorFeeActual);
    }

    function test_givenProceedsClaimed()
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
        givenLotProceedsAreClaimed
    {
        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);

        uint256 claimableBids = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual =
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT) * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY) + _curatorMaxPotentialFee
            - claimableBids - curatorFeeActual;

        // Assert balances
        _assertBaseTokenBalances(unusedCapacity, claimableBids, curatorFeeActual);
    }

    function test_givenProceedsClaimed_givenBidsClaimed()
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
        givenLotProceedsAreClaimed
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenBidIsClaimed(_bidIds[0])
    {
        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);

        uint256 claimableBids = 0;
        uint256 curatorFeeActual =
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT) * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY) + _curatorMaxPotentialFee
            - _scaleBaseTokenAmount(_BID_AMOUNT_OUT) - curatorFeeActual;

        // Assert balances
        _assertBaseTokenBalances(unusedCapacity, claimableBids, curatorFeeActual);
    }

    function test_givenBidsClaimed()
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
        givenBidIsClaimed(_bidIds[0])
    {
        // Call function
        vm.prank(_CURATOR);
        _auctionHouse.claimCuratorPayout(_lotId);

        uint256 claimableBids = 0;
        uint256 curatorFeeActual =
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT) * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY) + _curatorMaxPotentialFee
            - claimableBids - curatorFeeActual;

        // Assert balances
        _assertBaseTokenBalances(unusedCapacity, claimableBids, curatorFeeActual);
    }

    function test_callerNotCurator()
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
        _auctionHouse.claimCuratorPayout(_lotId);

        uint256 claimableBids = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual =
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT) * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY) + _curatorMaxPotentialFee
            - claimableBids - curatorFeeActual;

        // Assert balances
        _assertBaseTokenBalances(unusedCapacity, claimableBids, curatorFeeActual);
    }
}
