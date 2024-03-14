// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract ClaimProceedsTest is AuctionHouseTest {
    uint96 internal constant _BID_AMOUNT = 2e18;
    uint96 internal constant _BID_AMOUNT_OUT = 2e18;

    uint96 internal constant _BID_AMOUNT_PARTIAL_REFUND = 15e17;
    uint96 internal constant _BID_AMOUNT_OUT_PARTIAL_PAYOUT = 1e18;

    function _assertQuoteTokenBalances(
        uint256 sellerBalance,
        uint256 auctionHouseBalance
    ) internal {
        assertEq(
            _quoteToken.balanceOf(_SELLER),
            _callbackReceiveQuoteTokens ? 0 : sellerBalance,
            "quote token: seller"
        );
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            auctionHouseBalance,
            "quote token: auction house"
        );

        if (address(_callback) != address(0)) {
            assertEq(
                _quoteToken.balanceOf(address(_callback)),
                _callbackReceiveQuoteTokens ? sellerBalance : 0,
                "quote token: callback"
            );
        }
    }

    function _assertBaseTokenBalances(
        uint256 sellerBalance,
        uint256 auctionHouseBalance,
        uint256 curatorBalance
    ) internal {
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _callbackSendBaseTokens ? 0 : sellerBalance,
            "base token: seller"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            auctionHouseBalance,
            "base token: auction house"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), curatorBalance, "base token: curator");

        if (address(_callback) != address(0)) {
            assertEq(
                _baseToken.balanceOf(address(_callback)),
                _callbackSendBaseTokens ? sellerBalance : 0,
                "base token: callback"
            );
        }
    }

    function _assertLotRouting(uint256 funding) internal {
        // Check the lot
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, funding, "funding");

        // Check the lot status
        assertEq(uint8(_batchAuctionModule.lotStatus(_lotId)), uint8(Auction.Status.Claimed));
    }

    // ============ Modifiers ============ //

    modifier givenLotSettlementIsSuccessful() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            Auction.Settlement({
                totalIn: _scaleQuoteTokenAmount(_BID_AMOUNT),
                totalOut: _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
                pfBidder: address(0),
                pfReferrer: address(0),
                pfRefund: 0,
                pfPayout: 0,
                auctionOutput: ""
            })
        );

        _auctionHouse.settle(_lotId);
        _;
    }

    modifier givenLotSettlementIsFullCapacity() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            Auction.Settlement({
                totalIn: _scaleQuoteTokenAmount(_BID_AMOUNT * 5),
                totalOut: _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5),
                pfBidder: address(0),
                pfReferrer: address(0),
                pfRefund: 0,
                pfPayout: 0,
                auctionOutput: ""
            })
        );

        _auctionHouse.settle(_lotId);
        _;
    }

    modifier givenLotSettlementIsPartialFill() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            Auction.Settlement({
                totalIn: _scaleQuoteTokenAmount(_BID_AMOUNT * 6)
                    - _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND),
                totalOut: _scaleBaseTokenAmount(_LOT_CAPACITY),
                pfBidder: _bidder,
                pfReferrer: _REFERRER,
                pfRefund: _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND),
                pfPayout: _scaleBaseTokenAmount(_BID_AMOUNT_OUT_PARTIAL_PAYOUT),
                auctionOutput: ""
            })
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
    // [X] given it is not a batch auction
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
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));
    }

    function test_notBatchAuction_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotIsConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
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
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableRefund);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_lotSettlementSuccessful_givenCurated()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_lotSettlementIsFullCapacity_givenCurated()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint256 claimablePayout =
            _scaleBaseTokenAmount(_LOT_CAPACITY - _BID_AMOUNT_OUT_PARTIAL_PAYOUT);
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint256 claimablePayout =
            _scaleBaseTokenAmount(_LOT_CAPACITY - _BID_AMOUNT_OUT_PARTIAL_PAYOUT);
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint256 claimablePayout =
            _scaleBaseTokenAmount(_LOT_CAPACITY - _BID_AMOUNT_OUT_PARTIAL_PAYOUT);
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_lotSettlementIsPartialFill_givenCurated()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
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
        uint256 claimablePayout =
            _scaleBaseTokenAmount(_LOT_CAPACITY - _BID_AMOUNT_OUT_PARTIAL_PAYOUT);
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint256 claimablePayout =
            _scaleBaseTokenAmount(_LOT_CAPACITY - _BID_AMOUNT_OUT_PARTIAL_PAYOUT);
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
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
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
        _assertLotRouting(claimablePayout);

        assertEq(_callback.lotClaimedProceeds(_lotId), true, "lotClaimedProceeds");
    }
}
