// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {BatchAuction} from "src/modules/auctions/BatchAuctionModule.sol";

import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";

import {BatchAuctionHouseTest} from "test/BatchAuctionHouse/AuctionHouseTest.sol";

contract BatchClaimProceedsTest is BatchAuctionHouseTest {
    uint256 internal constant _BID_AMOUNT = 2e18;
    uint256 internal constant _BID_AMOUNT_OUT = 2e18;

    uint256 internal constant _BID_AMOUNT_PARTIAL_REFUND = 15e17;
    uint256 internal constant _BID_AMOUNT_OUT_PARTIAL_PAYOUT = 1e18;

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

    // ============ Test Cases ============ //

    // [X] when the lot id is invalid
    //  [X] it reverts
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
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
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
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidParams.selector);
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
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND));
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
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
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND));
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
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
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND));
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
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
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND));
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
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
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND));
        _assertBaseTokenBalances(unusedCapacity, claimablePayout + curatorFeeActual);
        _assertLotRouting(claimablePayout);
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

        assertEq(_callback.lotClaimedProceeds(_lotId), true, "lotClaimedProceeds");
    }
}
