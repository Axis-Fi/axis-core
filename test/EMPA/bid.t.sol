// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaBidTest is EmpaTest {
    uint96 internal constant _BID_AMOUNT = 1e18;

    // bid
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the auction is cancelled
    //  [X] it reverts
    // [X] given the auction is concluded
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
    // [X] it records the bid

    function test_whenLotIdIsInvalid_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        whenLotIdIsInvalid
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );
    }

    function test_givenLotIsCancelled_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasBeenCancelled
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketNotActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );
    }

    function test_givenLotIsConcluded_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketNotActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );
    }

    function test_incorrectAllowlistProof_reverts()
        external
        givenLotHasAllowlist
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        whenAllowlistProofIsIncorrect
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.NotPermitted.selector, _bidder);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );
    }

    function test_givenLotHasAllowlist()
        external
        givenLotHasAllowlist
        givenBidderIsOnAllowlist(_bidder, _allowlistProof)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );
    }

    function test_givenUserHasInsufficientBalance_reverts()
        public
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );
    }

    function test_whenPermit2ApprovalIsProvided()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        whenPermit2ApprovalIsProvided(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "_bidder: quote token balance mismatch");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _BID_AMOUNT,
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "_REFERRER mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuction.BidStatus.Submitted),
            "bidStatus mismatch"
        );
    }

    function test_whenPermit2ApprovalIsNotProvided()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "_bidder: quote token balance mismatch");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _BID_AMOUNT,
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "_REFERRER mismatch");
        assertEq(bid.amount, _BID_AMOUNT, "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuction.BidStatus.Submitted),
            "bidStatus mismatch"
        );
    }

    // [X] given there is no _PROTOCOL fee set for the auction type
    //  [X] the _PROTOCOL fee is not accrued
    // [X] the _PROTOCOL fee is not accrued

    function test_givenProtocolFeeIsSet()
        external
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            0,
            "quote token: _REFERRER rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _baseToken),
            0,
            "base token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _baseToken),
            0,
            "base token: _REFERRER rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken), 0, "base token: curator rewards mismatch"
        );
    }

    function test_givenProtocolFeeIsNotSet()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            0,
            "quote token: _REFERRER rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _baseToken),
            0,
            "base token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _baseToken),
            0,
            "base token: _REFERRER rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken), 0, "base token: curator rewards mismatch"
        );
    }

    // [X] given there is no _REFERRER fee set for the auction type
    //  [X] the _REFERRER fee is not accrued
    // [X] the _REFERRER fee is not accrued

    function test_givenReferrerFeeIsSet()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            0,
            "quote token: _REFERRER rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _baseToken),
            0,
            "base token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _baseToken),
            0,
            "base token: _REFERRER rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken), 0, "base token: curator rewards mismatch"
        );
    }

    function test_givenReferrerFeeIsNotSet()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            0,
            "quote token: _REFERRER rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _baseToken),
            0,
            "base token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _baseToken),
            0,
            "base token: _REFERRER rewards mismatch"
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
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the balances
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "curator: quote token balance mismatch");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "curator: base token balance mismatch");
    }

    function test_givenCuratorHasNotApproved()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the balances
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "curator: quote token balance mismatch");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "curator: base token balance mismatch");
    }

    function test_givenCuratorHasApproved()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenOwnerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenOwnerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _BID_AMOUNT,
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );

        // Check the balances
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "curator: quote token balance mismatch");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "curator: base token balance mismatch");
    }

    // [X] given the quote token decimals are larger
    //  [X] it handles it
    // [X] given the base token decimals are larger
    //  [X] it handles it

    function test_whenPermit2ApprovalIsNotProvided_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.startPrank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );
        vm.stopPrank();

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "_bidder: quote token balance mismatch");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "_REFERRER mismatch");
        assertEq(bid.amount, _scaleQuoteTokenAmount(_BID_AMOUNT), "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuction.BidStatus.Submitted),
            "bidStatus mismatch"
        );
    }

    function test_whenPermit2ApprovalIsNotProvided_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidderHasQuoteTokenBalance(_BID_AMOUNT)
        givenBidderHasQuoteTokenAllowance(_BID_AMOUNT)
        whenBidAmountOutIsEncrypted(_BID_AMOUNT, 1e18)
    {
        // Call the function
        vm.startPrank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _encryptedBidAmountOut,
            _bidPublicKey,
            _allowlistProof,
            _permit2Data
        );
        vm.stopPrank();

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "_bidder: quote token balance mismatch");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            "auction house: quote token balance mismatch"
        );

        // Check the bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(bid.bidder, _bidder, "bidder mismatch");
        assertEq(bid.referrer, _REFERRER, "_REFERRER mismatch");
        assertEq(bid.amount, _scaleQuoteTokenAmount(_BID_AMOUNT), "amount mismatch");
        assertEq(bid.minAmountOut, 0, "minAmountOut mismatch");
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuction.BidStatus.Submitted),
            "bidStatus mismatch"
        );
    }
}
