// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaClaimTest is EmpaTest {
    uint96 internal constant _BID_AMOUNT = 1e18;
    uint96 internal constant _BID_AMOUNT_OUT = 2e18;

    uint96 internal constant _BID_SUCCESS_AMOUNT = 6e18;
    uint96 internal constant _BID_SUCCESS_AMOUNT_OUT = 3e18;

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the lot is not concluded
    //  [X] it reverts
    // [X] given the lot is not decrypted
    //  [X] it reverts
    // [X] given the lot is not settled
    //  [X] it reverts
    // [X] when the bid id is invalid
    //  [X] it reverts
    // [X] given the bid has been claimed
    //  [X] it reverts
    // [X] given the bid was not successful
    //  [X] given the caller is not the bidder
    //   [X] it refunds the bid amount to the bidder
    //  [X] it refunds the bid amount to the bidder
    // [X] given the caller is not the bidder
    //  [X] it sends the payout to the bidder
    // [X] it sends the payout to the bidder
    // [X] given the quote token decimals are larger
    //  [X] it correctly handles the claim
    // [X] given the quote token decimals are smaller
    //  [X] it correctly handles the claim

    function _assertAccruedFees(uint96 bidAmountIn_) internal {
        (uint24 protocolFeePercent, uint24 referrerFeePercent,) = _auctionHouse.fees();

        uint96 referrerFee_ = _mulDivUp(bidAmountIn_, referrerFeePercent, 1e5);
        uint96 protocolFee_ = _mulDivUp(bidAmountIn_, protocolFeePercent, 1e5);

        // Check accrued quote token fees
        assertEq(_auctionHouse.rewards(_REFERRER, _quoteToken), referrerFee_, "referrer fee");
        assertEq(_auctionHouse.rewards(_CURATOR, _quoteToken), 0, "curator fee"); // Always 0
        assertEq(_auctionHouse.rewards(_PROTOCOL, _quoteToken), protocolFee_, "protocol fee");
    }

    function test_invalidLotId_reverts() external {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenLotNotConcluded_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenLotNotDecrypted_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenLotNotSettled_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_invalidBidId_noBids_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Bid_InvalidId.selector, _lotId, _bidId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_invalidBidId_hasBids_reverts()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Bid_InvalidId.selector, _lotId, 0);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, 0);
    }

    function test_invalidBidId_hasBids_quoteTokenDecimalsLarger_reverts()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Bid_InvalidId.selector, _lotId, 0);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, 0);
    }

    function test_invalidBidId_hasBids_quoteTokenDecimalsSmaller_reverts()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Bid_InvalidId.selector, _lotId, 0);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, 0);
    }

    function test_givenBidClaimed_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Claim the bid
        _auctionHouse.claim(_lotId, _bidId);

        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Bid_AlreadyClaimed.selector);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);
    }

    function test_givenBidNotDecrypted()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenLargeBidIsCreated(_BID_AMOUNT, type(uint128).max)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), _BID_AMOUNT);
        assertEq(_baseToken.balanceOf(_bidder), 0);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        // Validate accrued fees
        _assertAccruedFees(0);
    }

    function test_givenBidNotSuccessful_givenCallerIsNotBidder()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), _BID_AMOUNT);
        assertEq(_baseToken.balanceOf(_bidder), 0);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        // Validate accrued fees
        _assertAccruedFees(0);
    }

    function test_givenBidNotSuccessful()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), _BID_AMOUNT);
        assertEq(_baseToken.balanceOf(_bidder), 0);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        // Validate accrued fees
        _assertAccruedFees(0);
    }

    function test_givenBidNotSuccessful_quoteTokenDecimalsLarger()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(_baseToken.balanceOf(_bidder), 0);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        // Validate accrued fees
        _assertAccruedFees(0);
    }

    function test_givenBidNotSuccessful_quoteTokenDecimalsSmaller()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), _scaleQuoteTokenAmount(_BID_AMOUNT));
        assertEq(_baseToken.balanceOf(_bidder), 0);

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        // Validate accrued fees
        _assertAccruedFees(0);
    }

    function test_givenBidSuccessful_givenCallerIsNotBidder()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_SUCCESS_AMOUNT, _BID_SUCCESS_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token balance");
        assertEq(_baseToken.balanceOf(_bidder), _BID_SUCCESS_AMOUNT_OUT, "base token balance");

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(
            uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed), "bid status"
        );

        // Validate accrued fees
        _assertAccruedFees(_BID_SUCCESS_AMOUNT);
    }

    function test_givenBidSuccessful()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_SUCCESS_AMOUNT, _BID_SUCCESS_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token balance");
        assertEq(_baseToken.balanceOf(_bidder), _BID_SUCCESS_AMOUNT_OUT, "base token balance");

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(
            uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed), "bid status"
        );

        // Validate accrued fees
        _assertAccruedFees(_BID_SUCCESS_AMOUNT);
    }

    function test_givenBidSuccessful_quoteTokenDecimalsLarger()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_SUCCESS_AMOUNT, _BID_SUCCESS_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token balance");
        assertEq(
            _baseToken.balanceOf(_bidder),
            _scaleBaseTokenAmount(_BID_SUCCESS_AMOUNT_OUT),
            "base token balance"
        );

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(
            uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed), "bid status"
        );

        // Validate accrued fees
        _assertAccruedFees(_scaleQuoteTokenAmount(_BID_SUCCESS_AMOUNT));
    }

    function test_givenBidSuccessful_quoteTokenDecimalsSmaller()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_SUCCESS_AMOUNT, _BID_SUCCESS_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claim(_lotId, _bidId);

        // Validate balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token balance");
        assertEq(
            _baseToken.balanceOf(_bidder),
            _scaleBaseTokenAmount(_BID_SUCCESS_AMOUNT_OUT),
            "base token balance"
        );

        // Validate bid status
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, _bidId);
        assertEq(
            uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed), "bid status"
        );

        // Validate accrued fees
        _assertAccruedFees(_scaleQuoteTokenAmount(_BID_SUCCESS_AMOUNT));
    }
}
