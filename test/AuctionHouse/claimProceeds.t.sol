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
        assertEq(_quoteToken.balanceOf(_SELLER), sellerBalance, "quote token: seller");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            auctionHouseBalance,
            "quote token: auction house"
        );
    }

    function _assertBaseTokenBalances(
        uint256 sellerBalance,
        uint256 auctionHouseBalance,
        uint256 curatorBalance
    ) internal {
        assertEq(_baseToken.balanceOf(_SELLER), sellerBalance, "base token: seller");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            auctionHouseBalance,
            "base token: auction house"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), curatorBalance, "base token: curator");
    }

    function _assertLotRouting(uint256 prefunding) internal {
        // Check the lot
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.prefunding, prefunding, "prefunding");

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
    // [ ] given it is not a batch auction
    //  [ ] it reverts
    // [X] given the auction is not pre-funded
    //  [X] given the lot did not settle
    //   [X] it sends the proceeds to the seller and marks the lot as claimed
    //  [X] given there is unused capacity
    //   [X] given the auction has curation enabled
    //    [X] it sends the proceeds and unused capacity and unused curator fees to the seller, and marks the lot as claimed
    //   [X] it sends the proceeds and unused capacity to the seller, and marks the lot as claimed
    //  [X] given the lot has a partial fill
    //   [X] given the auction has curation enabled
    //    [X] it sends the proceeds and unused capacity and unused curator fees to the seller, and marks the lot as claimed
    //   [X] it sends the proceeds and unused capacity to the seller, and marks the lot as claimed
    //  [X] it sends the proceeds to the seller and marks the lot as claimed
    // [X] given the auction is pre-funded
    //  [X] given the lot did not settle
    //   [X] it sends the unused capacity to the seller, and marks the lot as claimed
    //  [X] given the lot has a partial fill
    //   [X] given the auction has curation enabled
    //    [X] it sends the proceeds and unused capacity and unused curator fees to the seller, and marks the lot as claimed
    //   [X] it sends the proceeds and unused capacity to the seller, and marks the lot as claimed
    //  [X] given there is unused capacity
    //   [X] given the auction has curation enabled
    //    [X] it sends the proceeds and unused capacity and unused curator fees to the seller, and marks the lot as claimed
    //   [X] it sends the proceeds and unused capacity to the seller, and marks the lot as claimed
    //  [X] it sends the proceeds to the seller, and marks the lot as claimed
    // [ ] given the auction has hooks enabled
    //  [ ] it calls the onClaimProceeds callback, and marks the lot as claimed

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId);
    }

    function test_lotNotSettled()
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
        _auctionHouse.claimProceeds(_lotId);
    }

    function test_givenAlreadyClaimed()
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
        _auctionHouse.claimProceeds(_lotId);
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
        _auctionHouse.claimProceeds(_lotId);

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
        _auctionHouse.claimProceeds(_lotId);

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY) - claimablePayout;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_lotSettlementIsFullCapacity()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
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
        _auctionHouse.claimProceeds(_lotId);

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint96 curatorFeeActual = 0;
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
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
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
        _auctionHouse.claimProceeds(_lotId);

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
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
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
        _auctionHouse.claimProceeds(_lotId);

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
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
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
        _auctionHouse.claimProceeds(_lotId);

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

    function test_givenPrefunded_lotSettlementNotSuccessful()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenBatchAuctionRequiresPrefunding
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
        _auctionHouse.claimProceeds(_lotId);

        uint256 quoteTokenIn = 0;
        uint256 claimablePayout = 0;
        uint256 claimableRefund = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableRefund);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_givenPrefunded_lotSettlementSuccessful()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenBatchAuctionRequiresPrefunding
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
        _auctionHouse.claimProceeds(_lotId);

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 curatorFeeActual = 0;
        uint256 unusedCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY) - claimablePayout;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_givenPrefunded_givenCurated_lotSettlementSuccessful()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenBatchAuctionRequiresPrefunding
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
        _auctionHouse.claimProceeds(_lotId);

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

    function test_givenPrefunded_givenCurated_lotSettlementIsFullCapacity()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenBatchAuctionRequiresPrefunding
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
        _auctionHouse.claimProceeds(_lotId);

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 5);
        uint256 claimablePayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5);
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
        _assertLotRouting(claimablePayout);
    }

    function test_givenPrefunded_givenCurated_lotSettlementIsPartialFill()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenBatchAuctionRequiresPrefunding
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
        _auctionHouse.claimProceeds(_lotId);

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

    function test_givenPrefunded_lotSettlementIsPartialFill()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenBatchAuctionRequiresPrefunding
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
        _auctionHouse.claimProceeds(_lotId);

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
}
