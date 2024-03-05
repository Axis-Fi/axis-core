// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract ClaimProceedsTest is AuctionHouseTest {
    uint96 internal constant _BID_AMOUNT = 1e18;
    uint96 internal constant _BID_AMOUNT_OUT = 2e18;

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

    modifier givenLotSettlementIsNotSuccessful() {
        // Payout tokens will be returned to the seller
        _auctionHouse.settle(_lotId);
        _;
    }

    // ============ Test Cases ============ //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction is not settled
    //  [X] it reverts
    // [X] given the proceeds have already been claimed
    //  [X] it reverts
    // [ ] given it is not a batch auction
    //  [ ] it reverts
    // [X] given the auction is not pre-funded
    //  [X] given the lot did not settle
    //   [X] it marks the lot as claimed
    //  [X] it sends the proceeds to the seller and marks the lot as claimed
    // [X] given the auction is pre-funded
    //  [X] given the lot did not settle
    //   [X] it sends the unused capacity to the seller, and marks the lot as claimed
    //  [X] given there is unused capacity
    //   [X] given the auction has curation enabled
    //    [X] it sends the proceeds and unused capacity and unused curator fees to the seller, and marks the lot as claimed
    //   [X] it sends the proceeds and unused capacity to the seller, and marks the lot as claimed
    //  [X] it sends the proceeds to the seller, and marks the lot as claimed
    // [ ] given the auction has hooks enabled
    //  [ ] it calls the onClaimProceeds callback, and marks the lot as claimed

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
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
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
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
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
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

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_SELLER), 0, "quote token: seller");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            "quote token: auction house"
        ); // To be claimed by bidder

        // Assert base token balances
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "base token: seller"
        );
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Assert lot state
        // TODO update state?
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

        // Assert quote token balances
        assertEq(
            _quoteToken.balanceOf(_SELLER),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            "quote token: seller"
        );
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "quote token: auction house");

        // Assert base token balances
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _scaleBaseTokenAmount(_LOT_CAPACITY - _BID_AMOUNT_OUT),
            "base token: seller"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            "base token: auction house"
        ); // To be claimed by bidder
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Assert lot state
        // TODO update state?
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

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_SELLER), 0, "quote token: seller");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            "quote token: auction house"
        ); // To be claimed by bidder

        // Assert base token balances
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "base token: seller"
        );
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Assert lot state
        // TODO update state?
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

        // Assert quote token balances
        assertEq(
            _quoteToken.balanceOf(_SELLER),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            "quote token: seller"
        );
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "quote token: auction house");

        // Assert base token balances
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _scaleBaseTokenAmount(_LOT_CAPACITY - _BID_AMOUNT_OUT),
            "base token: seller"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            "base token: auction house"
        ); // To be claimed by bidder
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Assert lot state
        // TODO update state?
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

        // Calculate the curator fees
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;

        // Assert quote token balances
        assertEq(
            _quoteToken.balanceOf(_SELLER),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            "quote token: seller"
        );
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "quote token: auction house");

        // Assert base token balances
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _scaleBaseTokenAmount(
                _LOT_CAPACITY + _curatorMaxPotentialFee - _BID_AMOUNT_OUT - curatorFeeActual
            ),
            "base token: seller"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            "base token: auction house"
        ); // To be claimed by bidder
        assertEq(_baseToken.balanceOf(_CURATOR), curatorFeeActual, "base token: curator");

        // Assert lot state
        // TODO update state?
    }

    function test_givenPrefunded_givenCurated_fullCapacity_lotSettlementSuccessful()
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

        // Calculate the curator fees
        uint96 curatorFeeActual = _BID_AMOUNT_OUT * 5 * _curatorFeePercentActual / 1e5;

        // Assert quote token balances
        assertEq(
            _quoteToken.balanceOf(_SELLER),
            _scaleQuoteTokenAmount(_BID_AMOUNT * 5),
            "quote token: seller"
        );
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 0, "quote token: auction house");

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller"); // Nothing returned
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT * 5),
            "base token: auction house"
        ); // To be claimed by bidder
        assertEq(_baseToken.balanceOf(_CURATOR), curatorFeeActual, "base token: curator");

        // Assert lot state
        // TODO update state?
    }
}
