// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Mocks
import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";

// Auctions
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";

import {BatchAuctionHouseTest} from "test/BatchAuctionHouse/AuctionHouseTest.sol";

contract BatchBidTest is BatchAuctionHouseTest {
    uint256 internal constant _BID_AMOUNT = 1e18;

    address internal constant _SENDER = address(0x26);

    bytes internal _bidAuctionData = abi.encode("");

    // bid
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the auction is cancelled
    //  [X] it reverts
    // [X] given the auction is concluded
    //  [X] it reverts
    // [X] given the auction is settled
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
    // [X] when the bidder param is not the sender
    //  [X] when the bidder param is the zero address
    //    [X] it treats the sender as the bidder
    //    [X] when a callback is set
    //      [X] it sends the sender to the onBid callback
    //  [X] when the bidder param is not the zero address
    //    [X] it treats the bidder param as the bidder
    //    [X] when a callback is set
    //      [X] it sends the bidder param to the onBid callback

    function test_whenLotIdIsInvalid_reverts() external {
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, _lotId);
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
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

    // [X] given the referrer fee for the auction is zero
    //  [X] the referrer fee is not accrued
    // [X] given the referrer fee for the auction is not zero
    //  [X] the referrer fee is not accrued (doesn't happen until the bid is claimed)

    function test_givenReferrerFeeIsNonZero()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenMaxReferrerFeeIsSet
        givenReferrerFee(1_00)
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

    function test_givenReferrerFeeIsZero()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenMaxReferrerFeeIsSet
        givenReferrerFee(0)
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
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

    function test_whenBidderIsZeroAddress()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        _sendUserQuoteTokenBalance(_SENDER, _BID_AMOUNT);
        _approveUserQuoteTokenAllowance(_SENDER, _BID_AMOUNT);

        // Cache sender balance
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);

        // Call the function
        uint64 bidId = _createBid(_SENDER, address(0), _BID_AMOUNT, _bidAuctionData);

        // Check the bid
        MockBatchAuctionModule.Bid memory bid = _batchAuctionModule.getBid(_lotId, bidId);
        assertEq(bid.bidder, _SENDER, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "referrer mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");

        // Check that the sender's token balance was reduced
        assertEq(
            _quoteToken.balanceOf(_SENDER), senderBalance - _BID_AMOUNT, "sender balance mismatch"
        );
    }

    function test_whenBidderIsZeroAddress_whenCallbackIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
    {
        _sendUserQuoteTokenBalance(_SENDER, _BID_AMOUNT);
        _approveUserQuoteTokenAllowance(_SENDER, _BID_AMOUNT);

        // Cache sender balance
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);

        // Call the function
        uint64 bidId = _createBid(_SENDER, address(0), _BID_AMOUNT, _bidAuctionData);

        // Check the bid
        MockBatchAuctionModule.Bid memory bid = _batchAuctionModule.getBid(_lotId, bidId);
        assertEq(bid.bidder, _SENDER, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "referrer mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");

        // Check that the sender's token balance was reduced
        assertEq(
            _quoteToken.balanceOf(_SENDER), senderBalance - _BID_AMOUNT, "sender balance mismatch"
        );

        // Check that the callback was called and the bidder was sent to the callback
        assertEq(_callback.lotBid(_lotId), true, "lotBid");
        assertEq(_callback.bidder(_lotId, bidId), _SENDER, "bidder mismatch");
    }

    function test_whenBidderIsNotZeroAddress()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        _sendUserQuoteTokenBalance(_SENDER, _BID_AMOUNT);
        _approveUserQuoteTokenAllowance(_SENDER, _BID_AMOUNT);

        // Cache balances
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);
        uint256 bidderBalance = _quoteToken.balanceOf(_bidder);

        // Call the function
        uint64 bidId = _createBid(_SENDER, _bidder, _BID_AMOUNT, _bidAuctionData);

        // Check the bid
        MockBatchAuctionModule.Bid memory bid = _batchAuctionModule.getBid(_lotId, bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "referrer mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");

        // Check that the sender's token balance was reduced and the bidder's was not
        assertEq(
            _quoteToken.balanceOf(_SENDER), senderBalance - _BID_AMOUNT, "sender balance mismatch"
        );
        assertEq(_quoteToken.balanceOf(_bidder), bidderBalance, "bidder balance mismatch");
    }

    function test_whenBidderIsNotZeroAddress_whenCallbackIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
    {
        _sendUserQuoteTokenBalance(_SENDER, _BID_AMOUNT);
        _approveUserQuoteTokenAllowance(_SENDER, _BID_AMOUNT);

        // Cache balances
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);
        uint256 bidderBalance = _quoteToken.balanceOf(_bidder);

        // Call the function
        uint64 bidId = _createBid(_SENDER, _bidder, _BID_AMOUNT, _bidAuctionData);

        // Check the bid
        MockBatchAuctionModule.Bid memory bid = _batchAuctionModule.getBid(_lotId, bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "referrer mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");

        // Check that the sender's token balance was reduced and the bidder's was not
        assertEq(
            _quoteToken.balanceOf(_SENDER), senderBalance - _BID_AMOUNT, "sender balance mismatch"
        );
        assertEq(_quoteToken.balanceOf(_bidder), bidderBalance, "bidder balance mismatch");

        // Check that the callback was called and the bidder was sent to the callback
        assertEq(_callback.lotBid(_lotId), true, "lotBid");
        assertEq(_callback.bidder(_lotId, bidId), _bidder, "bidder mismatch");
    }
}
