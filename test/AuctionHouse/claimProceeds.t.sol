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

    Auction.BidClaim[] internal _bidClaims;

    function _assertQuoteTokenBalances(
        uint256 quoteTokenIn,
        uint256 claimableQuoteTokens
    ) internal {
        // Calculate fees
        uint256 totalFees =
            quoteTokenIn * (_protocolFeePercentActual + _referrerFeePercentActual) / 1e5;
        uint256 sellerBalance = quoteTokenIn - totalFees;

        assertEq(
            _quoteToken.balanceOf(_SELLER),
            _callbackReceiveQuoteTokens ? 0 : sellerBalance,
            "quote token: seller"
        );
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            claimableQuoteTokens + totalFees,
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
        uint256 unusedCapacity,
        uint256 claimableBids,
        uint256 claimableCuratorPayout
    ) internal {
        bool curatorPayoutClaimed = _batchAuctionModule.lotCuratorPayoutClaimed(_lotId);

        assertEq(
            _baseToken.balanceOf(_SELLER),
            _callbackSendBaseTokens ? 0 : unusedCapacity,
            "base token: seller"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            claimableBids + (curatorPayoutClaimed ? 0 : claimableCuratorPayout),
            "base token: auction house"
        );
        assertEq(
            _baseToken.balanceOf(_CURATOR),
            curatorPayoutClaimed ? claimableCuratorPayout : 0,
            "base token: curator"
        );

        if (address(_callback) != address(0)) {
            assertEq(
                _baseToken.balanceOf(address(_callback)),
                _callbackSendBaseTokens ? unusedCapacity : 0,
                "base token: callback"
            );
        }

        // Check the lot
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            lotRouting.funding,
            claimableBids + (curatorPayoutClaimed ? 0 : claimableCuratorPayout),
            "funding"
        );

        // Check the lot status
        assertEq(uint8(_batchAuctionModule.lotStatus(_lotId)), uint8(Auction.Status.Settled));

        // Check the lot proceeds claimed status
        assertEq(_batchAuctionModule.lotProceedsClaimed(_lotId), true);
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

    modifier givenLotSettlementIsFullCapacity() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            Auction.Settlement({
                totalIn: _scaleQuoteTokenAmount(_BID_AMOUNT * 5),
                totalOut: _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5),
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

    // ============ Test Cases ============ //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given it is not a batch auction
    //  [X] it reverts
    // [X] when protocol fees are set
    //  [X] it transfers the entire payment - protocol fees to the seller
    // [X] when referrer fees are set
    //  [X] it transfers the entire payment - referrer fees to the seller
    // [X] when protocol and referrer fees are set
    //  [X] it transfers the entire payment - protocol and referrer fees to the seller
    // [X] given the curator payout has been claimed
    //  [X] it excludes the curator payout from the seller refund
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
    }

    function test_lotSettlementSuccessful_givenBidsClaimed()
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

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT);
        uint256 claimedPayout = _scaleBaseTokenAmount(_BID_AMOUNT_OUT);
        uint256 claimablePayout = 0;
        uint256 curatorFeeActual =
            (claimedPayout + claimablePayout) * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity =
            _scaleBaseTokenAmount(_LOT_CAPACITY) - claimedPayout - claimablePayout;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, 0);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
    }

    function test_givenLotSettlementIsFullCapacity_givenCurated_givenBidsClaimed()
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
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint96 curatorFeeActual = 0;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
    }

    function test_givenCurated_lotSettlementIsFullCapacity_givenCuratorPayoutClaimed()
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
        givenCuratorPayoutIsClaimed
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
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
    }

    function test_givenCurated_lotSettlementIsPartialFill_givenCuratorPayoutClaimed()
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
        givenCuratorPayoutIsClaimed
    {
        // Call function
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));

        uint256 quoteTokenIn = _scaleQuoteTokenAmount(_BID_AMOUNT * 6 - _BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimableQuoteToken = _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint256 claimableQuoteToken = _scaleQuoteTokenAmount(_BID_AMOUNT_PARTIAL_REFUND);
        uint256 claimablePayout = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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
        uint96 curatorFeeActual = _LOT_CAPACITY * _curatorFeePercentActual / 1e5;
        uint256 unusedCapacity = 0;

        // Assert balances
        _assertQuoteTokenBalances(quoteTokenIn, claimableQuoteToken);
        _assertBaseTokenBalances(unusedCapacity, claimablePayout, curatorFeeActual);
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

        assertEq(_callback.lotClaimedProceeds(_lotId), true, "lotClaimedProceeds");
    }
}
