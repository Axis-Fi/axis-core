// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {EncryptedMarginalPriceAuction, FeeManager} from "src/EMPA.sol";

contract EmpaSettleTest is EmpaTest {
    uint96 internal constant _BID_PRICE_ONE_AMOUNT = 1e18;
    uint96 internal constant _BID_PRICE_ONE_AMOUNT_OUT = 1e18;
    uint96 internal constant _BID_PRICE_TWO_AMOUNT = 2e18;
    uint96 internal constant _BID_PRICE_TWO_AMOUNT_OUT = 1e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_TWO_AMOUNT = 4e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT = 2e18;
    uint96 internal constant _BID_SIZE_NINE_AMOUNT = 19e18;
    uint96 internal constant _BID_SIZE_NINE_AMOUNT_OUT = 9e18;
    uint96 internal constant _BID_PRICE_THREE_AMOUNT = 6e18;
    uint96 internal constant _BID_PRICE_THREE_AMOUNT_OUT = 2e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_TEN_AMOUNT = 20e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_TEN_AMOUNT_OUT = 10e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT = 22e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT_OUT = 11e18;

    uint96 internal _marginalPrice;

    uint96 internal _expectedReferrerFee;
    uint96 internal _expectedProtocolFee;
    uint96 internal _expectedAuctionHouseBaseTokenBalance;
    uint96 internal _expectedAuctionOwnerBaseTokenBalance;
    uint96 internal _expectedBidderBaseTokenBalance;
    uint96 internal _expectedCuratorBaseTokenBalance;
    uint96 internal _expectedAuctionHouseQuoteTokenBalance;
    uint96 internal _expectedAuctionOwnerQuoteTokenBalance;
    uint96 internal _expectedBidderQuoteTokenBalance;
    uint96 internal _expectedReferrerFeeAcrrued;
    uint96 internal _expectedProtocolFeeAcrrued;

    // ============ Modifiers ============ //

    modifier givenBidsAreBelowMinimumFilled() {
        // Capacity: 1 + 1 < 2.5 minimum
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);

        // Marginal price: 0 (due to not meeting minimum)
        _marginalPrice = 0;

        // Output
        // Bid one: 0 out
        // Bid two: 0 out

        // No fees collected

        _expectedAuctionHouseBaseTokenBalance = 0; // No bids filled
        _expectedAuctionOwnerBaseTokenBalance = _scaleBaseTokenAmount(_LOT_CAPACITY); // Unused capacity is returned
        _expectedBidderBaseTokenBalance = 0;
        _expectedCuratorBaseTokenBalance = 0;

        _expectedAuctionHouseQuoteTokenBalance =
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT); // To be claimed by the bidders
        _expectedAuctionOwnerQuoteTokenBalance = 0; // No payments
        _expectedBidderQuoteTokenBalance = 0;
        _;
    }

    modifier givenAllBidsAreBelowMinimumPrice() {
        // Capacity: 1 + 1 + 1 >= 2.5
        _createBid(_BID_PRICE_ONE_AMOUNT, _BID_PRICE_ONE_AMOUNT_OUT);
        _createBid(_BID_PRICE_ONE_AMOUNT, _BID_PRICE_ONE_AMOUNT_OUT);
        _createBid(_BID_PRICE_ONE_AMOUNT, _BID_PRICE_ONE_AMOUNT_OUT);

        // Marginal price: 0 (since 1 < 2 minimum)
        _marginalPrice = 0;

        // Output
        // Bid one: 0 out
        // Bid two: 0 out

        // No fees collected

        _expectedAuctionHouseBaseTokenBalance = 0; // No bids filled
        _expectedAuctionOwnerBaseTokenBalance = _scaleBaseTokenAmount(_LOT_CAPACITY); // Unused capacity is returned
        _expectedBidderBaseTokenBalance = 0;
        _expectedCuratorBaseTokenBalance = 0;

        _expectedAuctionHouseQuoteTokenBalance = _scaleQuoteTokenAmount(
            _BID_PRICE_ONE_AMOUNT + _BID_PRICE_ONE_AMOUNT + _BID_PRICE_ONE_AMOUNT
        ); // To be claimed by the bidders
        _expectedAuctionOwnerQuoteTokenBalance = 0; // No payments
        _expectedBidderQuoteTokenBalance = 0;
        _;
    }

    function _calculateReferrerFee(uint96 amountIn) internal view returns (uint96) {
        (, uint24 referrerFee,) = _auctionHouse.fees();

        return _mulDivUp(referrerFee, amountIn, 1e5);
    }

    function _calculateProtocolFee(uint96 amountIn) internal view returns (uint96) {
        (uint24 protocolFee,,) = _auctionHouse.fees();

        return _mulDivUp(protocolFee, amountIn, 1e5);
    }

    modifier givenBidsAreAboveMinimumAndBelowCapacity() {
        // Capacity: 1 + 1 + 1 + 1 >= 2.5 minimum && < 10 capacity
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);

        // Marginal price: 2 >= 2 (due to capacity not being reached and the last bid having a price of 2)
        _marginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);

        // Output
        // Bid one: 2 / 2 = 1 out
        // Bid two: 2 / 2 = 1 out
        // Bid three: 2 / 2 = 1 out
        // Bid four: 2 / 2 = 1 out

        uint96 bidAmountInTotal = _scaleQuoteTokenAmount(
            _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT
                + _BID_PRICE_TWO_AMOUNT
        );
        uint96 bidAmountOutTotal = _scaleBaseTokenAmount(
            _BID_PRICE_TWO_AMOUNT_OUT + _BID_PRICE_TWO_AMOUNT_OUT + _BID_PRICE_TWO_AMOUNT_OUT
                + _BID_PRICE_TWO_AMOUNT_OUT
        );

        // Fees
        _expectedReferrerFee = _calculateReferrerFee(bidAmountInTotal);
        _expectedProtocolFee = _calculateProtocolFee(bidAmountInTotal);

        _expectedAuctionHouseBaseTokenBalance = bidAmountOutTotal; // All bids filled
        _expectedAuctionOwnerBaseTokenBalance =
            _scaleBaseTokenAmount(_LOT_CAPACITY) - bidAmountOutTotal; // Unused capacity
        _expectedBidderBaseTokenBalance = 0; // To be claimed
        _expectedCuratorBaseTokenBalance = 0; // No curator fee set

        _expectedAuctionHouseQuoteTokenBalance = _expectedReferrerFee + _expectedProtocolFee; // All bids filled, nothing to be claimed
        _expectedAuctionOwnerQuoteTokenBalance =
            bidAmountInTotal - _expectedReferrerFee - _expectedProtocolFee; // Full payout
        _expectedBidderQuoteTokenBalance = 0;
        _;
    }

    modifier givenBidsAreOverSubscribed() {
        // Capacity: 9 + 2 > 10 capacity
        // Capacity reached on bid 2
        _createBid(_BID_SIZE_NINE_AMOUNT, _BID_SIZE_NINE_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_SIZE_TWO_AMOUNT, _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT);

        // Marginal price: 2 >= 2 (due to capacity being reached on bid 2)
        _marginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);

        // Output
        // Bid one: 19 / 2 = 9.5 out
        // Bid two: 10 - 9.5 = 0.5 out (partial fill)

        uint96 bidOneAmountOutActual = _mulDivUp(
            _scaleBaseTokenAmount(_BID_SIZE_NINE_AMOUNT),
            uint96(10 ** _quoteToken.decimals()),
            _marginalPrice
        ); // 9.5
        uint96 bidOneAmountInActual = _scaleQuoteTokenAmount(_BID_SIZE_NINE_AMOUNT); // 19
        uint96 bidTwoAmountOutActual = _auctionParams.capacity - bidOneAmountOutActual; // 0.5
        uint96 bidTwoAmountInActual = _mulDivUp(
            bidTwoAmountOutActual,
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        ); // 0.5 * 4 / 2 = 1

        uint96 bidAmountInSuccess = bidOneAmountInActual + bidTwoAmountInActual;
        uint96 bidAmountInFail =
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT) - bidTwoAmountInActual;

        // Fees
        _expectedReferrerFee = _calculateReferrerFee(bidAmountInSuccess);
        _expectedProtocolFee = _calculateProtocolFee(bidAmountInSuccess);
        _expectedReferrerFeeAcrrued = _calculateReferrerFee(bidTwoAmountInActual); // Accrued on partial fill
        _expectedProtocolFeeAcrrued = _calculateProtocolFee(bidTwoAmountInActual); // Accrued on partial fill

        _expectedAuctionHouseBaseTokenBalance = bidOneAmountOutActual; // To be claimed by the bidder
        _expectedAuctionOwnerBaseTokenBalance = 0; // No unused capacity
        _expectedBidderBaseTokenBalance = bidTwoAmountOutActual; // Partial fill transferred
        _expectedCuratorBaseTokenBalance = 0; // No curator fee set

        _expectedAuctionHouseQuoteTokenBalance = _expectedReferrerFee + _expectedProtocolFee; // Accrued fees
        _expectedAuctionOwnerQuoteTokenBalance = bidOneAmountInActual + bidTwoAmountInActual
            - _expectedReferrerFee - _expectedProtocolFee; // Actual payout minus fees
        _expectedBidderQuoteTokenBalance = bidAmountInFail; // Partial fill returned
        _;
    }

    modifier givenBidsAreOverSubscribedRespectsOrdering() {
        // Capacity: 10 + 2 > 10 capacity
        // Capacity reached on bid 1 (which is processed second)
        _createBid(_BID_PRICE_TWO_SIZE_TEN_AMOUNT, _BID_PRICE_TWO_SIZE_TEN_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_SIZE_TWO_AMOUNT, _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT);

        // Marginal price: 2 >= 2 (due to capacity being reached on bid 1)
        _marginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);

        // Output
        // Bid two: 4 / 2 = 2 out
        // Bid one: 10 - 2 = 8 out (partial fill)

        uint96 bidTwoAmountOutActual = _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT); // 2
        uint96 bidTwoAmountInActual = _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT); // 4
        uint96 bidOneAmountOutActual = _auctionParams.capacity - bidTwoAmountOutActual; // 8
        uint96 bidOneAmountInActual = _mulDivUp(
            bidOneAmountOutActual,
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TEN_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TEN_AMOUNT_OUT)
        ); // 8 * 20 / 10 = 16

        uint96 bidAmountInSuccess = bidOneAmountInActual + bidTwoAmountInActual;
        uint96 bidAmountInFail =
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TEN_AMOUNT) - bidOneAmountInActual;

        // Fees
        _expectedReferrerFee = _calculateReferrerFee(bidAmountInSuccess);
        _expectedProtocolFee = _calculateProtocolFee(bidAmountInSuccess);
        _expectedReferrerFeeAcrrued = _calculateReferrerFee(bidOneAmountInActual); // Accrued on partial fill
        _expectedProtocolFeeAcrrued = _calculateProtocolFee(bidOneAmountInActual); // Accrued on partial fill

        _expectedAuctionHouseBaseTokenBalance = bidTwoAmountOutActual; // To be claimed by the bidder
        _expectedAuctionOwnerBaseTokenBalance = 0; // No unused capacity
        _expectedBidderBaseTokenBalance = bidOneAmountOutActual; // Partial fill transferred
        _expectedCuratorBaseTokenBalance = 0; // No curator fee set

        _expectedAuctionHouseQuoteTokenBalance = _expectedReferrerFee + _expectedProtocolFee; // Accrued fees
        _expectedAuctionOwnerQuoteTokenBalance = bidOneAmountInActual + bidTwoAmountInActual
            - _expectedReferrerFee - _expectedProtocolFee; // Actual payout minus fees
        _expectedBidderQuoteTokenBalance = bidAmountInFail; // Partial fill returned
        _;
    }

    modifier givenBidsAreOverSubscribedOnFirstBid() {
        // Capacity: 11 > 10 capacity
        // Capacity reached on bid 1
        _createBid(_BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT, _BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT_OUT);

        // Marginal price: 2 >= 2 (due to capacity being reached on bid 1)
        _marginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);

        // Output
        // Bid one: 10 out (partial fill)

        uint96 bidOneAmountOutActual = _auctionParams.capacity;
        uint96 bidOneAmountInActual = _mulDivUp(
            bidOneAmountOutActual,
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT_OUT)
        );

        uint96 bidAmountInSuccess = bidOneAmountInActual;
        uint96 bidAmountInFail =
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT) - bidOneAmountInActual;

        // Fees
        _expectedReferrerFee = _calculateReferrerFee(bidAmountInSuccess);
        _expectedProtocolFee = _calculateProtocolFee(bidAmountInSuccess);
        _expectedReferrerFeeAcrrued = _calculateReferrerFee(bidOneAmountInActual); // Accrued on partial fill
        _expectedProtocolFeeAcrrued = _calculateProtocolFee(bidOneAmountInActual); // Accrued on partial fill

        _expectedAuctionHouseBaseTokenBalance = 0; // Partial fill transferred
        _expectedAuctionOwnerBaseTokenBalance = 0; // No unused capacity
        _expectedBidderBaseTokenBalance = bidOneAmountOutActual; // Partial fill transferred
        _expectedCuratorBaseTokenBalance = 0; // No curator fee set

        _expectedAuctionHouseQuoteTokenBalance = _expectedReferrerFee + _expectedProtocolFee; // Accrued fees
        _expectedAuctionOwnerQuoteTokenBalance =
            bidOneAmountInActual - _expectedReferrerFee - _expectedProtocolFee; // Actual payout minus fees
        _expectedBidderQuoteTokenBalance = bidAmountInFail; // Partial fill returned
        _;
    }

    modifier givenSomeBidsAreBelowMinimumPrice() {
        // Capacity: 2 + 2 + 1 + 1 >= 2.5 minimum
        _createBid(_BID_PRICE_THREE_AMOUNT, _BID_PRICE_THREE_AMOUNT_OUT);
        _createBid(_BID_PRICE_THREE_AMOUNT, _BID_PRICE_THREE_AMOUNT_OUT);
        _createBid(_BID_PRICE_ONE_AMOUNT, _BID_PRICE_ONE_AMOUNT_OUT);
        _createBid(_BID_PRICE_ONE_AMOUNT, _BID_PRICE_ONE_AMOUNT_OUT);

        // Marginal price: 3 >= 2 (due to capacity not being reached and the last bid above the minimum having a price of 3)
        _marginalPrice = _scaleQuoteTokenAmount(3 * _BASE_SCALE);

        // Output
        // Bid one: 6 / 3 = 2 out
        // Bid two: 6 / 3 = 2 out
        // Bid three: 0 out
        // Bid four: 0 out

        uint96 bidAmountInSuccess =
            _scaleQuoteTokenAmount(_BID_PRICE_THREE_AMOUNT + _BID_PRICE_THREE_AMOUNT);
        uint96 bidAmountInFail =
            _scaleQuoteTokenAmount(_BID_PRICE_ONE_AMOUNT + _BID_PRICE_ONE_AMOUNT);
        uint96 bidAmountOutSuccess =
            _scaleBaseTokenAmount(_BID_PRICE_THREE_AMOUNT_OUT + _BID_PRICE_THREE_AMOUNT_OUT);

        // Fees
        _expectedReferrerFee = _calculateReferrerFee(bidAmountInSuccess);
        _expectedProtocolFee = _calculateProtocolFee(bidAmountInSuccess);

        _expectedAuctionHouseBaseTokenBalance = bidAmountOutSuccess; // To be claimed by bidders
        _expectedAuctionOwnerBaseTokenBalance =
            _scaleBaseTokenAmount(_LOT_CAPACITY) - bidAmountOutSuccess; // Unused capacity
        _expectedBidderBaseTokenBalance = 0; // To be claimed
        _expectedCuratorBaseTokenBalance = 0; // No curator fee set

        _expectedAuctionHouseQuoteTokenBalance =
            bidAmountInFail + _expectedReferrerFee + _expectedProtocolFee; // Accrued fees and failed bids to be refunded
        _expectedAuctionOwnerQuoteTokenBalance =
            bidAmountInSuccess - _expectedReferrerFee - _expectedProtocolFee; // Full payout
        _expectedBidderQuoteTokenBalance = 0;
        _;
    }

    function _mulDivUp(uint96 mul1_, uint96 mul2_, uint96 div_) internal pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivUp(mul1_, mul2_, div_);
        if (product > type(uint96).max) revert("overflow");

        return uint96(product);
    }

    // ============ Tests ============ //

    function _assertBaseTokenBalances() internal {
        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _expectedAuctionHouseBaseTokenBalance,
            "base token: auction house balance"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner),
            _expectedAuctionOwnerBaseTokenBalance,
            "base token: owner balance"
        );
        assertEq(
            _baseToken.balanceOf(_bidder),
            _expectedBidderBaseTokenBalance,
            "base token: bidder balance"
        );
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(
            _baseToken.balanceOf(_CURATOR),
            _expectedCuratorBaseTokenBalance,
            "base token: curator balance"
        );
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");
    }

    function _assertQuoteTokenBalances() internal {
        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _expectedAuctionHouseQuoteTokenBalance,
            "quote token: auction house balance"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _expectedAuctionOwnerQuoteTokenBalance,
            "quote token: owner balance"
        );
        assertEq(
            _quoteToken.balanceOf(_bidder),
            _expectedBidderQuoteTokenBalance,
            "quote token: bidder balance"
        );
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function _assertAccruedFees() internal {
        // Check accrued quote token fees
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            _expectedReferrerFeeAcrrued,
            "referrer fee"
        );
        assertEq(_auctionHouse.rewards(_CURATOR, _quoteToken), 0, "curator fee"); // Always 0
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            _expectedProtocolFeeAcrrued,
            "protocol fee"
        );
    }

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot has not concluded
    //   [X] it reverts
    // [X] when the lot has not been decrypted
    //   [X] it reverts
    // [X] when the lot has been settled already
    //   [X] it reverts
    // [ ] when the marginal price overflows
    //  [ ] it reverts

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    function test_lotNotConcluded_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    function test_lotNotDecrypted_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    function test_lotAlreadySettled_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    // [X] when the filled amount is less than the lot minimum
    //   [X] it returns no winning bids, and the base tokens are returned to the owner
    // [X] when the marginal price is less than the minimum price
    //   [X] it returns no winning bids, and the base tokens are returned to the owner
    // [X] given the filled capacity is greater than the lot minimum
    //  [X] it returns winning bids, with the marginal price is the minimum price
    // [X] given some of the bids fall below the minimum price
    //  [X] it returns winning bids, excluding those below the minimum price
    // [X] given the lot is over-subscribed with a partial fill
    //  [X] it returns winning bids, with the marginal price is the price at which the lot capacity is exhausted, and a partial fill for the lowest winning bid, last bidder receives the partial fill and is returned excess quote tokens
    // [X] given that the quote token decimals are larger than the base token decimals
    //  [X] it succeeds
    // [X] given that the quote token decimals are smaller than the base token decimals
    //  [X] it succeeds
    // [X] it succeeds - auction owner receives quote tokens (minus fees), bidders receive base tokens and fees accrued

    function test_bidsLessThanMinimumFilled()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreBelowMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice);

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_marginalPriceLessThanMinimum()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenAllBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice);

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_filledCapacityGreaterThanMinimum()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreAboveMinimumAndBelowCapacity
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice);

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_filledCapacityGreaterThanMinimum_quoteTokenDecimalsLarger()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreAboveMinimumAndBelowCapacity
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(
            uint8(lot.status),
            uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled),
            "lot status"
        );

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_filledCapacityGreaterThanMinimum_quoteTokenDecimalsSmaller()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreAboveMinimumAndBelowCapacity
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(
            uint8(lot.status),
            uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled),
            "lot status"
        );

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_someBidsBelowMinimumPrice()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenSomeBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_someBidsBelowMinimumPrice_quoteTokenDecimalsLarger()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenSomeBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_someBidsBelowMinimumPrice_quoteTokenDecimalsSmaller()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenSomeBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribed
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 2);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_quoteTokenDecimalsLarger()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribed
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 2);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_quoteTokenDecimalsSmaller()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribed
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 2);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_ordering()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribedRespectsOrdering
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1); // Bid one is processed second due to insertion order
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_ordering_quoteTokenDecimalsLarger()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribedRespectsOrdering
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1); // Bid one is processed second due to insertion order
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_ordering_quoteTokenDecimalsSmaller()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribedRespectsOrdering
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1); // Bid one is processed second due to insertion order
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_singleBid_partialFill()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribedOnFirstBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_singleBid_partialFill_quoteTokenDecimalsLarger()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribedOnFirstBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_singleBid_partialFill_quoteTokenDecimalsSmaller()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenProtocolFeeIsSet(_PROTOCOL_FEE_PERCENT)
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribedOnFirstBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 1);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    // [X] given that the referrer fee is set
    //  [X] the referrer fee is accrued, referrer fee is deducted from payment

    function test_partialFill_referrerFeeIsSet()
        external
        givenReferrerFeeIsSet(_REFERRER_FEE_PERCENT)
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreOverSubscribed
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, _marginalPrice, "marginal price");

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Validate status of partial fill bid
        EncryptedMarginalPriceAuction.Bid memory bid = _getBid(_lotId, 2);
        assertEq(uint8(bid.status), uint8(EncryptedMarginalPriceAuction.BidStatus.Claimed));

        uint96 bidOneAmountOutActual = _mulDivUp(_BID_SIZE_NINE_AMOUNT, 1e18, _marginalPrice); // 9.5
        uint96 bidOneAmountInActual = _BID_SIZE_NINE_AMOUNT; // 19
        uint96 bidTwoAmountOutActual = _LOT_CAPACITY - bidOneAmountOutActual; // 0.5
        uint96 bidTwoAmountInActual = _mulDivUp(
            bidTwoAmountOutActual,
            _BID_PRICE_TWO_SIZE_TWO_AMOUNT,
            _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT
        ); // 0.5 * 4 / 2 = 1

        uint96 referrerFeeActual =
            _mulDivUp(bidOneAmountInActual + bidTwoAmountInActual, _REFERRER_FEE_PERCENT, 1e5);

        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            bidOneAmountOutActual,
            "base token: auction house balance"
        ); // To be claimed by the bidder
        assertEq(_baseToken.balanceOf(_auctionOwner), 0, "base token: owner balance"); // No unused capacity
        assertEq(_baseToken.balanceOf(_bidder), bidTwoAmountOutActual, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            referrerFeeActual,
            "quote token: auction house balance"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            bidOneAmountInActual + bidTwoAmountInActual - referrerFeeActual,
            "quote token: owner balance"
        );
        assertEq(
            _quoteToken.balanceOf(_bidder),
            _BID_PRICE_TWO_SIZE_TWO_AMOUNT - bidTwoAmountInActual,
            "quote token: bidder balance"
        );
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    // [X] given that the protocol fee is set
    //  [X] the protocol fee is accrued, protocol fee is deducted from payment
    //  [X] given that the referrer fee is set
    //   [X] the protocol and referrer fee are accrued, both fees deducted from payment

    // [ ] given there is a curator set
    //  [ ] payout token is transferred to the curator
}
