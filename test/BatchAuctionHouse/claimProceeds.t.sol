// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuctionModule} from "src/interfaces/IAuctionModule.sol";
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {BatchAuction} from "src/modules/auctions/BatchAuctionModule.sol";

import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";

import {BatchAuctionHouseTest} from "test/BatchAuctionHouse/AuctionHouseTest.sol";

contract BatchClaimProceedsTest is BatchAuctionHouseTest {
    uint256 internal constant _BID_AMOUNT = 2e18;
    uint256 internal constant _BID_AMOUNT_OUT = 2e18;

    uint256 internal constant _BID_AMOUNT_PARTIAL_REFUND = 15e17;
    uint256 internal constant _BID_AMOUNT_OUT_PARTIAL_PAYOUT = 1e18;

    BatchAuction.BidClaim[] internal _bidClaims;

    function _assertQuoteTokenBalances(
        uint256 totalInLessFees,
        uint256 claimableQuoteTokens
    ) internal {
        assertEq(
            _quoteToken.balanceOf(_SELLER),
            _callbackReceiveQuoteTokens ? 0 : totalInLessFees,
            "quote token: seller"
        );
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            claimableQuoteTokens,
            "quote token: auction house"
        );

        if (address(_callback) != address(0)) {
            assertEq(
                _quoteToken.balanceOf(address(_callback)),
                _callbackReceiveQuoteTokens ? totalInLessFees : 0,
                "quote token: callback"
            );
        }
    }

    function _assertBaseTokenBalances(uint256 capacityRefund, uint256 capacityAllocated) internal {
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _callbackSendBaseTokens ? 0 : capacityRefund,
            "base token: seller"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            capacityAllocated,
            "base token: auction house"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        if (address(_callback) != address(0)) {
            assertEq(
                _baseToken.balanceOf(address(_callback)),
                _callbackSendBaseTokens ? capacityRefund : 0,
                "base token: callback"
            );
        }
    }

    function _assertLotRouting(uint256 funding) internal {
        // Check the lot
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, funding, "funding");

        // Check the lot status
        assertEq(
            uint8(_batchAuctionModule.lotStatus(_lotId)),
            uint8(MockBatchAuctionModule.LotStatus.Settled)
        );

        // Check the lot proceeds claimed status
        assertEq(_batchAuctionModule.lotProceedsClaimed(_lotId), true);
    }

    function _assertRewards(uint256 capacityUtilised) internal {
        // Protocol and referrer rewards allocated when bids are claimed

        // Curator rewards are allocated in claimProceeds
        uint256 curatorRewards = capacityUtilised * _curatorFeePercentActual / 1e5;

        // Check the protocol rewards
        assertEq(_auctionHouse.rewards(_PROTOCOL, _quoteToken), 0, "quote token: protocol rewards");
        assertEq(_auctionHouse.rewards(_PROTOCOL, _baseToken), 0, "base token: protocol rewards");

        // Check the referrer rewards
        assertEq(_auctionHouse.rewards(_REFERRER, _quoteToken), 0, "quote token: referrer rewards");
        assertEq(_auctionHouse.rewards(_REFERRER, _baseToken), 0, "base token: referrer rewards");

        // Check the curator rewards
        assertEq(_auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards");
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken),
            curatorRewards,
            "base token: curator rewards"
        );
    }

    // ============ Modifiers ============ //

    modifier givenLotSettlementIsSuccessful() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId, _scaleQuoteTokenAmount(_BID_AMOUNT), _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        );

        _auctionHouse.settle(_lotId);
        _;
    }

    modifier givenLotSettlementIsFullCapacity() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            _scaleQuoteTokenAmount(_BID_AMOUNT * 5),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5)
        );

        _auctionHouse.settle(_lotId);
        _;
    }

    modifier givenLotSettlementIsPartialFill() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            _scaleQuoteTokenAmount(_BID_AMOUNT * 6)
                - _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND),
            _scaleBaseTokenAmount(_LOT_CAPACITY)
        );

        _auctionHouse.settle(_lotId);
        _;
    }

    modifier givenLotSettlementIsNotSuccessful() {
        // Payout tokens will be returned to the seller
        _auctionHouse.settle(_lotId);
        _;
    }

    /// @dev    Assumes that any amounts are scaled to the current decimal scale
    modifier givenPayoutIsSet(
        uint64 bidId_,
        address bidder_,
        address referrer_,
        uint256 amountIn_,
        uint256 payout_
    ) {
        _batchAuctionModule.addBidClaim(_lotId, bidId_, bidder_, referrer_, amountIn_, payout_, 0);
        _;
    }

    // ============ Test Cases ============ //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when protocol fees are set
    //  [X] it transfers the entire payment - protocol fees to the seller
    // [X] when referrer fees are set
    //  [X] it transfers the entire payment - referrer fees to the seller
    // [X] when protocol and referrer fees are set
    //  [X] it transfers the entire payment - protocol and referrer fees to the seller
    // [X] given the lot did not settle
    //  [X] it sends the unused capacity to the seller, and marks the lot as claimed
    // [X] given the lot has a partial fill
    //  [X] given the auction has curation enabled
    //   [X] it sends the proceeds and unused capacity and unused curator fees to the seller, and marks the lot as claimed
    //  [X] it sends the proceeds and unused capacity to the seller, and marks the lot as claimed
    // [X] given there is unused capacity
    //  [X] given the auction has curation enabled
    //   [X] it sends the proceeds and unused capacity and unused curator fees to the seller, and marks the lot as claimed
    //  [X] it sends the proceeds and unused capacity to the seller, and marks the lot as claimed
    // [X] it sends the proceeds to the seller, and marks the lot as claimed
    // [X] given the auction capacity was filled
    //  [X] given the base token is a revert on zero token
    //   [X] it does not revert
    // [X] given the auction has callbacks enabled
    //  [X] given the callback has the receive quote tokens flag
    //   [X] it refunds quote tokens to the callback
    //  [X] given the callback has the receive base tokens flag
    //   [X] it sends the proceeds to the callback
    //  [X] it calls the onClaimProceeds callback

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));
    }

    function test_lotNotSettled_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionModule.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));
    }

    function test_givenAlreadyClaimed_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
        givenLotProceedsAreClaimed
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionModule.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));
    }

    function test_lotSettlementNotSuccessful()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = 0;
        uint256 claimablePayout = 0;
        uint256 claimableRefund = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableRefund);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementNotSuccessful_givenRevertOnZero()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenIsRevertOnZero
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = 0;
        uint256 claimablePayout = 0;
        uint256 claimableRefund = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableRefund);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_lotSettlementSuccessful()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY) - claimablePayout;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementSuccessful_givenCurated()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
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

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementSuccessful_givenCurated_givenCuratorFeeNotSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
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

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_givenLotSettlementIsFullCapacity_givenBidsClaimed()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT * 5))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT * 5))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT * 5), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
        givenPayoutIsSet(
            1,
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT * 5),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5)
        )
        givenBidIsClaimed(1)
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimedPayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint256 claimablePayout = 0; // Claimed
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity =
            _scaleBaseTokenAmount(_LOT_CAPACITY) - claimedPayout - claimablePayout;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout + claimedPayout);
    }

    function test_givenLotSettlementIsFullCapacity_givenCurated_givenBidsClaimed()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT * 5))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT * 5))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT * 5), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
        givenPayoutIsSet(
            1,
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT * 5),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5)
        )
        givenBidIsClaimed(1)
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimedPayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint256 claimablePayout = 0; // Claimed
        uint256 curatorFeeActual = _curatorMaxPotentialFee;
        uint256 unusedCapacity =
            _scaleBaseTokenAmount(_LOT_CAPACITY) - claimedPayout - claimablePayout;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout + claimedPayout);
    }

    function test_lotSettlementIsFullCapacity()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsFullCapacity_givenCurated()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsFullCapacity_givenCurated_givenCuratorFeeNotSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsFullCapacity_givenProtocolFeeIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsFullCapacity_givenReferrerFeeIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsFullCapacity_givenProtocolFeeIsSet_givenReferrerFeeIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsFullCapacity_givenRevertOnZero()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenBaseTokenIsRevertOnZero
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_lotSettlementIsPartialFill()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsPartialFill
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 6 - _BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimableQuoteToken = _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsPartialFill_givenBidsClaimed()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsPartialFill
        givenPayoutIsSet(
            1,
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenBidIsClaimed(1)
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 6 - _BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimableQuoteToken = _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY - _BID_AMOUNT_OUT);
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_givenCurated_lotSettlementIsFullCapacity()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_givenCurated_givenCuratorFeeNotSet_lotSettlementIsFullCapacity()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsFullCapacity
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_givenCurated_lotSettlementIsPartialFill()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsPartialFill
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 6 - _BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimableQuoteToken = _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_givenCurated_givenCuratorFeeNotSet_lotSettlementIsPartialFill()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsPartialFill
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 6 - _BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimableQuoteToken = _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsPartialFill_givenCurated()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsPartialFill
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 6 - _BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimableQuoteToken = _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementIsPartialFill_givenCurated_givenCuratorFeeNotSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenLotIsConcluded
        givenLotSettlementIsPartialFill
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 6 - _BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimableQuoteToken = _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);
    }

    function test_lotSettlementSuccessful_givenCallbackIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCallbackIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
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

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);

        assertEq(_callback.lotClaimedProceeds(_lotId), true, "lotClaimedProceeds");
    }

    function test_lotSettlementSuccessful_givenCallbackIsSet_givenReceiveQuoteTokensFlag()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
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

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);

        assertEq(_callback.lotClaimedProceeds(_lotId), true, "lotClaimedProceeds");
    }

    function test_lotSettlementSuccessful_givenCallbackIsSet_givenSendBaseTokensFlag()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
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

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
        _assertRewards(claimablePayout);

        assertEq(_callback.lotClaimedProceeds(_lotId), true, "lotClaimedProceeds");
    }
}
