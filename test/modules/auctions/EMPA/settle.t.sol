// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Module} from "src/modules/Modules.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

import {EmpaModuleTest} from "test/modules/auctions/EMPA/EMPAModuleTest.sol";

import {console2} from "forge-std/console2.sol";

contract EmpaModuleSettleTest is EmpaModuleTest {
    uint96 internal constant _BID_PRICE_BELOW_ONE_AMOUNT = 1e18;
    uint96 internal constant _BID_PRICE_BELOW_ONE_AMOUNT_OUT = 2e18;
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
    uint96 internal constant _BID_PRICE_OVERFLOW_AMOUNT = type(uint96).max;
    uint96 internal constant _BID_PRICE_OVERFLOW_AMOUNT_OUT = 1e17;
    uint96 internal constant _BID_PRICE_TEN = 10e18;
    uint96 internal constant _BID_PRICE_TEN_OUT = 1e18;

    uint96 internal constant _LOT_CAPACITY_OVERFLOW = type(uint96).max - 10;

    uint96 internal _expectedMarginalPrice;
    uint64 internal _expectedMarginalBidId;
    uint96 internal _expectedTotalIn;
    uint96 internal _expectedTotalOut;
    address internal _expectedPartialFillBidder;
    address internal _expectedPartialFillReferrer;
    uint96 internal _expectedPartialFillRefund;
    uint96 internal _expectedPartialFillPayout;
    bytes internal _expectedAuctionOutput = bytes("");

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot has not concluded
    //   [X] it reverts
    // [X] when the lot has not been decrypted
    //   [X] it reverts
    // [X] when the lot has been settled already
    //   [X] it reverts
    // [X] given the lot has been cancelled
    //  [X] it reverts
    // [X] when the lot proceeds have been claimed
    //  [X] it reverts
    // [X] when the caller is not the parent
    //   [X] it reverts

    // [X] when the filled amount is less than the lot minimum
    //  [X] it handles different token decimals
    //  [X] it returns no amounts in and out, and no partial fill
    // [X] when the marginal price is less than the minimum price
    //  [X] it handles different token decimals
    //  [X] it returns no amounts in and out, and no partial fill
    // [X] given the filled capacity is greater than the lot minimum
    //  [X] it handles different token decimals
    //  [X] it returns the amounts in and out, and no partial fill
    // [X] given some of the bids fall below the minimum price
    //  [X] it handles different token decimals
    //  [X] it returns the amounts in and out, excluding those below the minimum price, and no partial fill
    // [X] given a bid sets a marginal price that results in the previous bid exceeding the capacity
    //  [X] it handles different token decimals
    //  [X] given the bid is the last bid
    //   [X] it calculates a marginal price that results in complete utilisation of the capacity, and no partial fill
    //  [X] given the bid is not the last bid
    //   [X] it calculates a marginal price that results in complete utilisation of the capacity, and no partial fill
    // [X] given a bid's marginal price does not result in the lot capacity being filled, but is above the minimum filled
    //  [X] given the bid is the last bid
    //   [X] it sets the marginal price to the bid price, and returns the amounts in and out
    //  [X] given the bid is not the last bid
    //   [X] it sets the marginal price to the bid price, and returns the amounts in and out
    // [X] given a bid's marginal price does not result in the minimum filled being reached, but the minimum price results in capacity being filled
    //   [X] given the bid is the last bid
    //    [X] it sets the marginal price to the price that will fill capacity, and returns the amounts in and out
    //   [X] given the bid is not the last bid
    //    [X] it sets the marginal price to the bid price, and returns the amounts in and out
    // [X] given the lot capacity is exactly met
    //  [X] it handles different token decimals
    //  [X] it returns the amounts in and out, and no partial fill
    // [X] given the lot has a single bid and is over-subscribed
    //  [X] it handles different token decimals
    //  [X] it returns the amounts in and out, with the marginal price is the price at which the lot capacity is exhausted, and a partial fill for the single bid
    // [X] given the lot is over-subscribed with a partial fill
    //  [X] it handles different token decimals
    //  [X] it respects the ordering of the bids
    //  [X] it returns the amounts in and out, with the marginal price is the price at which the lot capacity is exhausted, and a partial fill for the lowest winning bid

    // [X] given the expended capacity results in a uint96 overflow
    //  [X] the settle function does not revert

    function _settle()
        internal
        returns (Auction.Settlement memory settlement_, bytes memory auctionOutput_)
    {
        vm.prank(address(_auctionHouse));
        (settlement_, auctionOutput_) = _module.settle(_lotId);

        return (settlement_, auctionOutput_);
    }

    function _assertSettlement(
        Auction.Settlement memory settlement_,
        bytes memory auctionOutput_
    ) internal {
        assertEq(settlement_.totalIn, _expectedTotalIn, "totalIn");
        assertEq(settlement_.totalOut, _expectedTotalOut, "totalOut");
        assertEq(settlement_.pfBidder, _expectedPartialFillBidder, "pfBidder");
        assertEq(settlement_.pfReferrer, _expectedPartialFillReferrer, "pfReferrer");
        assertEq(settlement_.pfRefund, _expectedPartialFillRefund, "pfRefund");
        assertEq(settlement_.pfPayout, _expectedPartialFillPayout, "pfPayout");
        assertEq(auctionOutput_, _expectedAuctionOutput, "auctionOutput");

        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalBidId, _expectedMarginalBidId, "marginalBidId");
    }

    function _assertLot() internal {
        // Check that the lot has been updated
        Auction.Lot memory lotData = _getAuctionLot(_lotId);

        assertEq(lotData.sold, _expectedTotalOut, "lot sold");
        assertEq(lotData.purchased, _expectedTotalIn, "lot purchased");
        assertEq(lotData.capacity, 0, "lot capacity");
        assertEq(lotData.partialPayout, _expectedPartialFillPayout, "lot partialPayout");
    }

    modifier givenBidsAreBelowMinimumFilled() {
        // Capacity: 1 + 1 < 2.5 minimum
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_ONE_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_ONE_AMOUNT_OUT)
        );

        // Marginal price: max (due to not meeting minimum)
        _expectedMarginalPrice = type(uint96).max;

        // Output
        // Bid one: 0 out
        // Bid two: 0 out
        _;
    }

    modifier givenAllBidsAreBelowMinimumPrice() {
        // Marginal price 0.5, used capacity 2, exits as it is below the minimum price
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT_OUT)
        );
        // Not considered
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT_OUT)
        );
        // Not considered
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT_OUT)
        );

        // Marginal price: max (since 0.5 < 1 minimum)
        _expectedMarginalPrice = type(uint96).max;

        // Output
        // Bid one: 0 out
        // Bid two: 0 out
        // Bid three: 0 out
        _;
    }

    modifier givenNotLastBidAndAboveMinimumFilled() {
        // Marginal price 2, total in 2, used capacity 1, continues as below lot capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        // Marginal price 2, total in 4, used capacity 2, continues as below lot capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        // Marginal price 2, total in 6, used capacity 3, continues as below lot capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        // Marginal price 2, total in 8, used capacity 4, continues as below lot capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        // Marginal price 0.5, so this bid is not considered.
        // Considering the previous bids, we calculate a marginal price of (2+2+2+2)/10 = 0.8, which is below the minimum price. Therefore, the marginal price is the minimum price: 1.
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT_OUT)
        );

        // Marginal price: 1
        _expectedMarginalPrice = _scaleQuoteTokenAmount(1 * _BASE_SCALE);

        // Output
        // Bid one: 2 / 1 = 2 out
        // Bid two: 2 / 1 = 2 out
        // Bid three: 2 / 1 = 2 out
        // Bid four: 2 / 1 = 2 out
        // Bid five: 0 out

        uint96 bidAmountInTotal = _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT * 4);
        uint96 bidAmountOutTotal = _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT * 4);

        _expectedTotalIn = bidAmountInTotal;
        _expectedTotalOut = bidAmountOutTotal;

        // No partial fill
        _;
    }

    modifier givenLastBidAndAboveMinimumFilled() {
        // Marginal price 2, total in 2, used capacity 1, continues as below lot capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        // Marginal price 2, total in 4, used capacity 2, continues as below lot capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        // Marginal price 2, total in 6, used capacity 3, continues as below lot capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        // Marginal price 2, total in 8, used capacity 4, continues as below lot capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT_OUT)
        );
        // On last bid, we calculate a marginal price to fill capacity of (2+2+2+2)/10 = 0.8, which is below the minimum price. Therefore, the marginal price is the minimum price: 1.

        // Marginal price: 1
        _expectedMarginalPrice = _scaleQuoteTokenAmount(1 * _BASE_SCALE);

        // Output
        // Bid one: 2 / 1 = 2 out
        // Bid two: 2 / 1 = 2 out
        // Bid three: 2 / 1 = 2 out
        // Bid four: 2 / 1 = 2 out

        uint96 bidAmountInTotal = _scaleQuoteTokenAmount(_BID_PRICE_TWO_AMOUNT * 4);
        uint96 bidAmountOutTotal = _scaleBaseTokenAmount(_BID_PRICE_TWO_AMOUNT * 4);

        _expectedTotalIn = bidAmountInTotal;
        _expectedTotalOut = bidAmountOutTotal;

        // No partial fill
        _;
    }

    modifier givenNotLastBidAndFilledBelowMinimumFilledAndAboveCapacityUsingMinimumPrice() {
        // Marginal price 10, total in 10, used capacity 1, continues as below lot min fill and capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TEN), _scaleBaseTokenAmount(_BID_PRICE_TEN_OUT)
        );
        // Marginal price 10, total in 20, used capacity 2, continues as below lot min fill and capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TEN), _scaleBaseTokenAmount(_BID_PRICE_TEN_OUT)
        );
        // Marginal price 0.5, so this bid is not considered.
        // Considering the previous bids, marginal price is 10, total in 20, used capacity 2. This is not above the minimum filled.
        // At the minimum price, used capacity is 20 / 1 = 20, which is more than the lot capacity and thus a fill is possible. The marginal price is determined as total in / capacity = 20 / 10 = 2.
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT_OUT)
        );

        // Marginal price: 2
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);

        // Output
        // Bid one: 10 / 2 = 5 out
        // Bid two: 10 / 2 = 5 out
        // Bid three: 0 out

        uint96 bidAmountInTotal = _scaleQuoteTokenAmount(_BID_PRICE_TEN + _BID_PRICE_TEN);
        uint96 bidAmountOutTotal = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _expectedTotalIn = bidAmountInTotal;
        _expectedTotalOut = bidAmountOutTotal;

        // No partial fill
        _;
    }

    modifier givenLastBidFilledBelowMinimumFilledAndAboveCapacityUsingMinimumPrice() {
        // Marginal price 10, total in 10, used capacity 1, continues as below lot min fill and capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TEN), _scaleBaseTokenAmount(_BID_PRICE_TEN_OUT)
        );
        // Marginal price 10, total in 20, used capacity 2, continues as below lot min fill and capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TEN), _scaleBaseTokenAmount(_BID_PRICE_TEN_OUT)
        );
        // Considering the previous bids, marginal price is 10, total in 20, used capacity 2. This is not above the minimum filled.
        // At the minimum price, used capacity is 20 / 1 = 20, which is more than the lot capacity and thus a fill is possible. The marginal price is determined as total in / capacity = 20 / 10 = 2.

        // Marginal price: 2
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);

        // Output
        // Bid one: 10 / 2 = 5 out
        // Bid two: 10 / 2 = 5 out

        uint96 bidAmountInTotal = _scaleQuoteTokenAmount(_BID_PRICE_TEN + _BID_PRICE_TEN);
        uint96 bidAmountOutTotal = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _expectedTotalIn = bidAmountInTotal;
        _expectedTotalOut = bidAmountOutTotal;

        // No partial fill
        _;
    }

    modifier givenBidsAreAboveMinimumAndBelowCapacity() {
        // Capacity: 2 + 2 + 2 + 2 >= 2.5 minimum && < 10 capacity
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );

        // Marginal price calculated between last bid price and minimum price as: (4+4+4+4)/10 = 1.6
        _expectedMarginalPrice = _scaleQuoteTokenAmount(16 * _BASE_SCALE / 10);

        // Output
        // Bid one: 4 / 1.6 = 2.5 out
        // Bid two: 4 / 1.6 = 2.5 out
        // Bid three: 4 / 1.6 = 2.5 out
        // Bid four: 4 / 1.6 = 2.5 out

        uint96 bidAmountInTotal = _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT * 4);
        uint96 bidAmountOutTotal = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _expectedTotalIn = bidAmountInTotal;
        _expectedTotalOut = bidAmountOutTotal;

        // No partial fill
        _;
    }

    modifier givenLotMarginalPriceBetweenBidsAndLastBid() {
        // Marginal price of 2.66667, used capacity of (8/2.66667) = 3, continues
        _createBid(_scaleQuoteTokenAmount(8e18), _scaleBaseTokenAmount(3e18));
        // Marginal price of 2, used capacity of (8+4)/2 = 6 < 10, continues but marginal price can be found between
        // this bid and the next one by calculating the marginal price that fills capacity: (8+4)/10 = 1.2
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );

        // Marginal price: 1.2 >= 1 (due to capacity being reached between bids 2 and 3)
        // Bid 1 & 2 fill capacity at a marginal price of 1.2, which is greater than the price of bid 3
        _expectedMarginalPrice = _scaleQuoteTokenAmount(12e17);

        // Output
        // Bid one: 8 / 1.2 = 6.667 out
        // Bid two: 4 / 1.2 = 3.333 out

        _expectedTotalIn = _scaleQuoteTokenAmount(12e18); // 12
        _expectedTotalOut = _scaleBaseTokenAmount(_LOT_CAPACITY); // 10

        // Partial fill
        // None
        _;
    }

    modifier givenLotMarginalPriceBetweenBidsAndNotLastBid() {
        // Marginal price of 2.66667, used capacity of (8/2.66667) = 3, continues
        _createBid(_scaleQuoteTokenAmount(8e18), _scaleBaseTokenAmount(3e18));
        // Marginal price of 2, used capacity of (8+4)/2 = 6 < 10, continues but marginal price can be found between
        // this bid and the next one by calculating the marginal price that fills capacity: (8+4)/10 = 1.2
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        // Marginal price of 1, this won't end up being considered
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_ONE_AMOUNT_OUT)
        );

        // Marginal price: 1.2 >= 1 (due to capacity being reached between bids 2 and 3)
        // Bid 1 & 2 fill capacity at a marginal price of 1.2, which is greater than the price of bid 3
        _expectedMarginalPrice = _scaleQuoteTokenAmount(12e17);

        // Output
        // Bid one: 8 / 1.2 = 6.667 out
        // Bid two: 4 / 1.2 = 3.333 out
        // Bid three: 0 out

        _expectedTotalIn = _scaleQuoteTokenAmount(12e18); // 12
        _expectedTotalOut = _scaleBaseTokenAmount(_LOT_CAPACITY); // 10

        // Partial fill
        // None
        _;
    }

    modifier givenLotCapacityIsMet() {
        // Capacity: 2 + 2 + 2 + 2 + 2 = 10 capacity
        // Capacity reached on bid 5
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );

        // Marginal price: 2 >= 1 (due to capacity being reached on bid 5)
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);
        _expectedMarginalBidId = 5;

        // Output
        // Bid one: 4 / 2 = 2 out
        // Bid two: 4 / 2 = 2 out
        // Bid three: 4 / 2 = 2 out
        // Bid four: 4 / 2 = 2 out
        // Bid five: 4 / 2 = 2 out

        uint96 bidAmountInSuccess = _scaleQuoteTokenAmount(
            _BID_PRICE_TWO_SIZE_TWO_AMOUNT + _BID_PRICE_TWO_SIZE_TWO_AMOUNT
                + _BID_PRICE_TWO_SIZE_TWO_AMOUNT + _BID_PRICE_TWO_SIZE_TWO_AMOUNT
                + _BID_PRICE_TWO_SIZE_TWO_AMOUNT
        );
        uint96 bidAmountOutSuccess = _scaleBaseTokenAmount(
            _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT + _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT
                + _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT + _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT
                + _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT
        );

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = bidAmountOutSuccess;

        // No partial fill
        _;
    }

    modifier givenLotIsOverSubscribed() {
        // Capacity: 9 + 2 > 10 capacity
        // Capacity reached on bid 2
        _createBid(
            _scaleQuoteTokenAmount(_BID_SIZE_NINE_AMOUNT),
            _scaleBaseTokenAmount(_BID_SIZE_NINE_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );

        // Marginal price: 2 >= 1 (due to capacity being reached on bid 2)
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);
        _expectedMarginalBidId = 2;

        // Output
        // Bid one: 19 / 2 = 9.5 out
        // Bid two: 10 - 9.5 = 0.5 out (partial fill)

        uint96 bidOneAmountOutActual = _mulDivUp(
            _scaleQuoteTokenAmount(_BID_SIZE_NINE_AMOUNT),
            uint96(10 ** _baseTokenDecimals),
            _expectedMarginalPrice
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
        uint96 bidAmountOutSuccess = bidOneAmountOutActual + bidTwoAmountOutActual;

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = bidAmountOutSuccess;

        // Partial fill
        _expectedPartialFillBidder = _BIDDER;
        _expectedPartialFillReferrer = _REFERRER;
        _expectedPartialFillRefund = bidAmountInFail;
        _expectedPartialFillPayout = bidTwoAmountOutActual;
        _;
    }

    modifier givenLotIsOverSubscribedRespectsOrdering() {
        // Capacity: 10 + 2 > 10 capacity
        // Capacity reached on bid 1 (which is processed second)
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TEN_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TEN_AMOUNT_OUT)
        );

        // Marginal price: 2 >= 1 (due to capacity being reached on bid 1)
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);
        _expectedMarginalBidId = 2;

        // Output
        // Bid one: 4 / 2 = 2 out
        // Bid two: 10 - 2 = 8 out (partial fill)

        uint96 bidOneAmountOutActual = _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT); // 2
        uint96 bidOneAmountInActual = _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TWO_AMOUNT); // 4
        uint96 bidTwoAmountOutActual = _auctionParams.capacity - bidOneAmountOutActual; // 8
        uint96 bidTwoAmountInActual = _mulDivUp(
            bidTwoAmountOutActual,
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TEN_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_TEN_AMOUNT_OUT)
        ); // 8 * 20 / 10 = 16

        uint96 bidAmountInSuccess = bidOneAmountInActual + bidTwoAmountInActual;
        uint96 bidAmountInFail =
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_TEN_AMOUNT) - bidTwoAmountInActual;
        uint96 bidAmountOutSuccess = bidOneAmountOutActual + bidTwoAmountOutActual;

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = bidAmountOutSuccess;

        // Partial fill
        _expectedPartialFillBidder = _BIDDER;
        _expectedPartialFillReferrer = _REFERRER;
        _expectedPartialFillRefund = bidAmountInFail;
        _expectedPartialFillPayout = bidTwoAmountOutActual;
        _;
    }

    modifier givenLotIsOverSubscribedOnFirstBid() {
        // Capacity: 11 > 10 capacity
        // Capacity reached on bid 1
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_TWO_SIZE_ELEVEN_AMOUNT_OUT)
        );

        // Marginal price: 2 >= 1 (due to capacity being reached on bid 1)
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);
        _expectedMarginalBidId = 1;

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
        uint96 bidAmountOutSuccess = bidOneAmountOutActual;

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = bidAmountOutSuccess;

        // Partial fill
        _expectedPartialFillBidder = _BIDDER;
        _expectedPartialFillReferrer = _REFERRER;
        _expectedPartialFillRefund = bidAmountInFail;
        _expectedPartialFillPayout = bidOneAmountOutActual;
        _;
    }

    modifier givenSomeBidsAreBelowMinimumPrice() {
        // Capacity: 2 + 2 + 2 + 2 >= 2.5 minimum
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_THREE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_THREE_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_THREE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_THREE_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT_OUT)
        );
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT_OUT)
        );

        // Marginal price: 3 >= 1 (due to capacity not being reached and the last bid above the minimum having a price of 3)
        // Marginal price is calculated as the price at which the two valid bids fill the capacity: (6+6)/10 = 1.2
        _expectedMarginalPrice = _scaleQuoteTokenAmount(12 * _BASE_SCALE / 10);

        // Output
        // Bid one: 6 / 3 = 2 out
        // Bid two: 6 / 3 = 2 out
        // Bid three: 0 out
        // Bid four: 0 out

        uint96 bidAmountInSuccess =
            _scaleQuoteTokenAmount(_BID_PRICE_THREE_AMOUNT + _BID_PRICE_THREE_AMOUNT);
        uint96 bidAmountInFail =
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT + _BID_PRICE_BELOW_ONE_AMOUNT);
        uint96 bidAmountOutSuccess = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = bidAmountOutSuccess;

        // Partial fill
        // None
        _;
    }

    modifier givenBidsCauseCapacityOverflow() {
        uint96 bidOneAmount = 1e22;
        uint96 bidOneAmountOut = type(uint96).max - 1e24;
        uint96 bidTwoAmount = 1e22;
        uint96 bidTwoAmountOut = type(uint96).max - 1e24;

        // Capacity
        _createBid(_scaleQuoteTokenAmount(bidOneAmount), _scaleBaseTokenAmount(bidOneAmountOut));
        _createBid(_scaleQuoteTokenAmount(bidTwoAmount), _scaleBaseTokenAmount(bidTwoAmountOut));

        // Marginal price = 12621933
        _expectedMarginalPrice = _mulDivUp(bidTwoAmount, _BASE_SCALE, bidTwoAmountOut);
        _expectedMarginalBidId = 2;

        // These calculations mimic how the capacity usage is calculated in the settle function
        uint256 baseTokensRequired = FixedPointMathLib.mulDivDown(
            bidOneAmount + bidTwoAmount, _BASE_SCALE, _expectedMarginalPrice
        );
        uint256 bidTwoAmountOutFull =
            FixedPointMathLib.mulDivDown(bidTwoAmount, _BASE_SCALE, _expectedMarginalPrice);
        uint256 bidTwoAmountOutOverflow = baseTokensRequired - _LOT_CAPACITY_OVERFLOW;

        // Output
        // Bid one: bidOneAmountOut out
        // Bid two: 90 out (partial fill)

        uint96 bidOneAmountInActual = bidOneAmount;
        uint96 bidOneAmountOutActual =
            _mulDivDown(bidOneAmount, _BASE_SCALE, _expectedMarginalPrice);
        uint96 bidTwoAmountOutActual = uint96(bidTwoAmountOutFull - bidTwoAmountOutOverflow);
        uint96 bidTwoAmountInActual = uint96(
            FixedPointMathLib.mulDivUp(bidTwoAmount, bidTwoAmountOutActual, bidTwoAmountOutFull)
        );

        uint96 bidAmountInSuccess = bidOneAmountInActual + bidTwoAmountInActual;
        uint96 bidAmountInFail = bidTwoAmount - bidTwoAmountInActual;

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = _LOT_CAPACITY_OVERFLOW;

        // Partial fill
        _expectedPartialFillBidder = _BIDDER;
        _expectedPartialFillReferrer = _REFERRER;
        _expectedPartialFillRefund = bidAmountInFail;
        _expectedPartialFillPayout = bidTwoAmountOutActual;
        _;
    }

    modifier givenLargeNumberOfUnfilledBids() {
        // Create 10 bids that will fill capacity
        for (uint256 i; i < 10; i++) {
            _createBid(2e18, 1e18);
        }

        // Create more bids that will not be filled
        // Lower price, otherwise they will be filled first due to ordering
        for (uint256 i; i < 1500; i++) {
            _createBid(19e17, 1e18);
        }

        // Marginal price: 2
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2 * _BASE_SCALE);
        _expectedMarginalBidId = 10;

        _expectedTotalIn = 10 * 2e18;
        _expectedTotalOut = 10 * 1e18;
        _;
    }

    modifier givenMarginalPriceRoundingLastBid() {
        _createBid(
            _scaleQuoteTokenAmount(12e18 - 1), // 11999999999999999999
            _scaleBaseTokenAmount(4e18)
        );
        _createBid(_scaleQuoteTokenAmount(8e18), _scaleBaseTokenAmount(4e18));

        // Total amount in: 11999999999999999999 + 8e18 = 20e18-1
        // Price of bid 2: 8e18 * 1e18 / 4e18 = 2e18
        // Total amount out: (20e18-1) * 1e18 / 2e18 = 10e18-1 // 9999999999999999999
        // Marginal price: 2
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2e18);
        _expectedMarginalBidId = 2; // Otherwise bid 2 will not be able to claim

        // Output
        // Bid one: (12e18 - 1) / 2 = 6e18-1 out
        // Bid two: 8 / 2 = 4 out

        uint96 bidAmountInSuccess = _scaleQuoteTokenAmount(12e18 - 1 + 8e18);
        uint96 bidAmountOutSuccess = _scaleBaseTokenAmount(_LOT_CAPACITY - 1);

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = bidAmountOutSuccess;

        // Partial fill
        // None
        _;
    }

    modifier givenMarginalPriceRoundingNotLastBid() {
        _createBid(
            _scaleQuoteTokenAmount(12e18 - 1), // 11999999999999999999
            _scaleBaseTokenAmount(4e18)
        );
        _createBid(_scaleQuoteTokenAmount(8e18), _scaleBaseTokenAmount(4e18));
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_BELOW_ONE_AMOUNT_OUT)
        );

        // Total amount in: 11999999999999999999 + 8e18 = 20e18-1
        // Price of bid 2: 8e18 * 1e18 / 4e18 = 2e18
        // Total amount out: (20e18-1) * 1e18 / 2e18 = 10e18-1 // 9999999999999999999
        // Marginal price: 2
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2e18);
        _expectedMarginalBidId = 2; // Otherwise bid 2 will not be able to claim

        // Output
        // Bid one: (12e18 - 1) / 2 = 6e18-1 out
        // Bid two: 8 / 2 = 4 out
        // Bid three: 0 out

        uint96 bidAmountInSuccess = _scaleQuoteTokenAmount(12e18 - 1 + 8e18);
        uint96 bidAmountOutSuccess = _scaleBaseTokenAmount(_LOT_CAPACITY - 1);

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = bidAmountOutSuccess;

        // Partial fill
        // None
        _;
    }

    modifier givenMarginalPriceRoundingThenCapacityExceeded() {
        _createBid(
            _scaleQuoteTokenAmount(12e18 - 1), // 11999999999999999999
            _scaleBaseTokenAmount(4e18)
        );
        _createBid(_scaleQuoteTokenAmount(8e18), _scaleBaseTokenAmount(4e18));
        // This will be considered, as capacity expended (9999999999999999999) is not greater than capacity (10e18)
        _createBid(
            _scaleQuoteTokenAmount(_BID_PRICE_ONE_AMOUNT),
            _scaleBaseTokenAmount(_BID_PRICE_ONE_AMOUNT_OUT)
        );

        // Total amount in: 11999999999999999999 + 8e18 + 1e18 = 21e18-1
        // Marginal price: 2
        _expectedMarginalPrice = _scaleQuoteTokenAmount(2e18);
        _expectedMarginalBidId = 2; // Otherwise bid 2 will not be able to claim

        // Output
        // Bid one: (12e18 - 1) / 2 = 6e18-1 out
        // Bid two: 8 / 2 = 4 out
        // Bid three: 0 out as it will round down to 0

        uint96 bidAmountInSuccess = _scaleQuoteTokenAmount(12e18 - 1 + 8e18);
        uint96 bidAmountOutSuccess = _scaleBaseTokenAmount(_LOT_CAPACITY - 1);

        _expectedTotalIn = bidAmountInSuccess;
        _expectedTotalOut = bidAmountOutSuccess;

        // Partial fill
        // None
        _;
    }

    // ============ Tests ============ //

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        _settle();
    }

    function test_lotHasNotConcluded_reverts() external givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call function
        _settle();
    }

    function test_privateKeyNotSubmitted_reverts()
        external
        givenLotIsCreated
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call function
        _settle();
    }

    function test_lotHasNotBeenDecrypted_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_TWO_SIZE_TWO_AMOUNT, _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call function
        _settle();
    }

    function test_lotHasAlreadyBeenSettled_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_TWO_SIZE_TWO_AMOUNT, _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call function
        _settle();
    }

    function test_lotCancelled_reverts() external givenLotIsCreated givenLotIsCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        _settle();
    }

    function test_lotProceedsAreClaimed_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_TWO_SIZE_TWO_AMOUNT, _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
        givenLotProceedsAreClaimed
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuctionModule.Auction_WrongState.selector, _lotId
        );
        vm.expectRevert(err);

        // Call function
        _settle();
    }

    function test_callerNotParent_reverts()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidIsCreated(_BID_PRICE_TWO_SIZE_TWO_AMOUNT, _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT)
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call function
        _module.settle(_lotId);
    }

    function test_bidsLessThanMinimumFilled()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreBelowMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_bidsLessThanMinimumFilled_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreBelowMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_bidsLessThanMinimumFilled_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreBelowMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_marginalPriceLessThanMinimumPrice()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenAllBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_marginalPriceLessThanMinimumPrice_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenAllBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_marginalPriceLessThanMinimumPrice_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenAllBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_bidsAboveMinimumAndBelowCapacity()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreAboveMinimumAndBelowCapacity
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_bidsAboveMinimumAndBelowCapacity_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreAboveMinimumAndBelowCapacity
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_bidsAboveMinimumAndBelowCapacity_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreAboveMinimumAndBelowCapacity
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_someBidsBelowMinimumPrice()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenSomeBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_someBidsBelowMinimumPrice_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenSomeBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_someBidsBelowMinimumPrice_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenSomeBidsAreBelowMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_largeNumberOfUnfilledBids_gasUsage()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLargeNumberOfUnfilledBids
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        uint256 gasBefore = gasleft();
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();
        uint256 gasAfter = gasleft();
        console2.log("gas used", gasBefore - gasAfter);

        // Validate auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.marginalPrice, _expectedMarginalPrice, "marginalPrice");
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_marginalPriceBetweenBids_givenLastBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotMarginalPriceBetweenBidsAndLastBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_marginalPriceBetweenBids_givenLastBid_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenLotMarginalPriceBetweenBidsAndLastBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_marginalPriceBetweenBids_givenLastBid_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenLotMarginalPriceBetweenBidsAndLastBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_marginalPriceBetweenBids_givenNotLastBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotMarginalPriceBetweenBidsAndNotLastBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_marginalPriceBetweenBids_givenNotLastBid_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenLotMarginalPriceBetweenBidsAndNotLastBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_marginalPriceBetweenBids_givenNotLastBid_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenLotMarginalPriceBetweenBidsAndNotLastBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_notLastBid_aboveMinimumFilled()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenNotLastBidAndAboveMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_notLastBid_aboveMinimumFilled_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenNotLastBidAndAboveMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_notLastBid_aboveMinimumFilled_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenNotLastBidAndAboveMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_lastBid_aboveMinimumFilled()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLastBidAndAboveMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_lastBid_aboveMinimumFilled_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenLastBidAndAboveMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_lastBid_aboveMinimumFilled_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenLastBidAndAboveMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_filledBelowMinimumFilled_aboveCapacityUsingMinimumPrice_givenNotLastBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenNotLastBidAndFilledBelowMinimumFilledAndAboveCapacityUsingMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_filledBelowMinimumFilled_aboveCapacityUsingMinimumPrice_givenNotLastBid_quoteTokenDecimalsLarger(
    )
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenNotLastBidAndFilledBelowMinimumFilledAndAboveCapacityUsingMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_filledBelowMinimumFilled_aboveCapacityUsingMinimumPrice_givenNotLastBid_quoteTokenDecimalsSmaller(
    )
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenNotLastBidAndFilledBelowMinimumFilledAndAboveCapacityUsingMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_filledBelowMinimumFilled_aboveCapacityUsingMinimumPrice_givenLastBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLastBidFilledBelowMinimumFilledAndAboveCapacityUsingMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_filledBelowMinimumFilled_aboveCapacityUsingMinimumPrice_givenLastBid_quoteTokenDecimalsLarger(
    )
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenLastBidFilledBelowMinimumFilledAndAboveCapacityUsingMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
    }

    function test_filledBelowMinimumFilled_aboveCapacityUsingMinimumPrice_givenLastBid_quoteTokenDecimalsSmaller(
    )
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenLastBidFilledBelowMinimumFilledAndAboveCapacityUsingMinimumPrice
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_lotCapacityIsMet()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotCapacityIsMet
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_lotCapacityIsMet_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenLotCapacityIsMet
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_lotCapacityIsMet_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenLotCapacityIsMet
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenLotIsOverSubscribedOnFirstBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsOverSubscribedOnFirstBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenLotIsOverSubscribedOnFirstBid_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsOverSubscribedOnFirstBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenLotIsOverSubscribedOnFirstBid_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsOverSubscribedOnFirstBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenLotIsOverSubscribed()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsOverSubscribed
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenLotIsOverSubscribed_quoteTokenDecimalsLarger()
        external
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsOverSubscribed
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenLotIsOverSubscribed_quoteTokenDecimalsSmaller()
        external
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsOverSubscribed
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenLotIsOverSubscribed_respectsOrdering()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenLotIsOverSubscribedRespectsOrdering
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenBidsCauseCapacityOverflow()
        external
        givenMinimumPrice(1)
        givenLotCapacity(_LOT_CAPACITY_OVERFLOW)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsCauseCapacityOverflow
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenBidAmountRespectsRoundingLastBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenMarginalPriceRoundingLastBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenBidAmountRespectsRoundingNotLastBid()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenMarginalPriceRoundingNotLastBid
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }

    function test_givenMarginalPriceRoundingThenCapacityExceeded()
        external
        givenLotIsCreated
        givenLotHasStarted
        givenMarginalPriceRoundingThenCapacityExceeded
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        (Auction.Settlement memory settlement, bytes memory auctionOutput) = _settle();

        // Assert settlement
        _assertSettlement(settlement, auctionOutput);
        _assertLot();
    }
}
