// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Mocks
import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";

// Auctions
import {Auction} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract BidTest is AuctionHouseTest {
    uint96 internal constant _BID_AMOUNT = 1e18;

    bytes internal _bidAuctionData = abi.encode("");

    // bid
    // [X] given the auction is atomic
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the auction is cancelled
    //  [X] it reverts
    // [X] given the auction is concluded
    //  [X] it reverts
    // [X] given the auction is settled
    //  [X] it reverts
    // [X] given the auction proceeds have been claimed
    //  [X] it reverts
    // [X] given the auction has an allowlist
    //  [X] reverts if the sender is not on the allowlist
    //  [X] it succeeds
    // [X] given the user does not have sufficient balance of the quote token
    //  [X] it reverts
    // [X] when Permit2 approval is provided
    //  [X] it transfers the tokens from the sender using Permit2
    // [X] when Permit2 approval is not provided
    //  [X] it transfers the tokens from the sender
    // [X] given the auction has callbacks
    //  [X] it calls the callback
    // [X] it records the bid

    function test_givenAtomicAuction_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_whenLotIdIsInvalid_reverts() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_givenLotIsCancelled_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotIsCancelled
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_givenLotIsConcluded_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotIsConcluded
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_givenLotIsSettled_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotIsConcluded
        givenLotIsSettled
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_givenLotProceedsHaveBeenClaimed_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotIsConcluded
        givenLotIsSettled
        givenLotProceedsAreClaimed
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_incorrectAllowlistProof_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotHasAllowlist
        givenLotIsCreated
        givenLotHasStarted
        whenAllowlistProofIsIncorrect
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        bytes memory err = abi.encodePacked("not allowed");
        vm.expectRevert(err);

        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_givenLotHasAllowlist()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotHasAllowlist
        givenLotIsCreated
        givenLotHasStarted
        whenAllowlistProofIsCorrect
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_givenUserHasInsufficientBalance_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);
    }

    function test_whenPermit2ApprovalIsProvided()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        whenPermit2ApprovalIsProvided(_BID_AMOUNT)
    {
        // Call the function
        uint64 bidId = _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "_bidder: quote token balance mismatch");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _BID_AMOUNT,
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        MockBatchAuctionModule.Bid memory bid = _batchAuctionModule.getBid(_lotId, bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "referrer mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
    }

    function test_whenPermit2ApprovalIsNotProvided()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        uint64 bidId = _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "_bidder: quote token balance mismatch");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _BID_AMOUNT,
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        MockBatchAuctionModule.Bid memory bid = _batchAuctionModule.getBid(_lotId, bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "referrer mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
    }

    function test_whenAuctionParamIsProvided()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        _bidAuctionData = abi.encode("auction data");

        // Call the function
        uint64 bidId = _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the bid
        MockBatchAuctionModule.Bid memory bid = _batchAuctionModule.getBid(_lotId, bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "referrer mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
    }

    function test_givenCallbackIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        uint64 bidId = _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "_bidder: quote token balance mismatch");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _BID_AMOUNT,
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        MockBatchAuctionModule.Bid memory bid = _batchAuctionModule.getBid(_lotId, bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "referrer mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");

        // Check the callback
        assertEq(_callback.lotBid(_lotId), true, "lotBid");
    }

    // [X] given there is no protocol fee set for the auction type
    //  [X] the protocol fee is not accrued
    // [X] the protocol fee is not accrued

    function test_givenProtocolFeeIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: protocol rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            0,
            "quote token: referrer rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _baseToken), 0, "base token: protocol rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _baseToken), 0, "base token: referrer rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken), 0, "base token: curator rewards mismatch"
        );
    }

    function test_givenProtocolFeeIsNotSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: protocol rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            0,
            "quote token: referrer rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _baseToken), 0, "base token: protocol rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _baseToken), 0, "base token: referrer rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken), 0, "base token: curator rewards mismatch"
        );
    }

    // [X] given there is no referrer fee set for the auction type
    //  [X] the referrer fee is not accrued
    // [X] the referrer fee is not accrued

    function test_givenReferrerFeeIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: protocol rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            0,
            "quote token: referrer rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _baseToken), 0, "base token: protocol rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _baseToken), 0, "base token: referrer rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken), 0, "base token: curator rewards mismatch"
        );
    }

    function test_givenReferrerFeeIsNotSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: protocol rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            0,
            "quote token: referrer rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _baseToken), 0, "base token: protocol rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _baseToken), 0, "base token: referrer rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken), 0, "base token: curator rewards mismatch"
        );
    }

    // [X] given there is no curator set
    //  [X] no payout token is transferred to the curator
    // [X] given there is a curator set
    //  [X] given the curator has not approved curation
    //   [X] no payout token is transferred to the curator
    //  [X] no payout token is transferred to the curator

    function test_givenCuratorIsNotSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the balances
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "curator: quote token balance mismatch");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "curator: base token balance mismatch");
    }

    function test_givenCuratorHasNotApproved()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorMaxFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the balances
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "curator: quote token balance mismatch");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "curator: base token balance mismatch");
    }

    function test_givenCuratorHasApproved()
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
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Call the function
        _createBid(_BID_AMOUNT, _bidAuctionData);

        // Check the balances
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "curator: quote token balance mismatch");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "curator: base token balance mismatch");
    }
}
