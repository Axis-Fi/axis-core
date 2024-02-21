// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaSettleTest is EmpaTest {
    uint96 internal constant _BID_PRICE_ONE_AMOUNT = 1e18;
    uint96 internal constant _BID_PRICE_ONE_AMOUNT_OUT = 1e18;
    uint96 internal constant _BID_PRICE_TWO_AMOUNT = 2e18;
    uint96 internal constant _BID_PRICE_TWO_AMOUNT_OUT = 1e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_TWO_AMOUNT = 4e18;
    uint96 internal constant _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT = 2e18;
    uint96 internal constant _BID_SIZE_BELOW_MINIMUM_AMOUNT = 1e15;
    uint96 internal constant _BID_SIZE_BELOW_MINIMUM_AMOUNT_OUT = 1e16;
    uint96 internal constant _BID_SIZE_NINE_AMOUNT = 19e18;
    uint96 internal constant _BID_SIZE_NINE_AMOUNT_OUT = 9e18;
    uint96 internal constant _BID_PRICE_THREE_AMOUNT = 6e18;
    uint96 internal constant _BID_PRICE_THREE_AMOUNT_OUT = 2e18;

    uint96 internal _marginalPrice;

    uint96 internal _bidAmountInTotal;
    uint96 internal _bidAmountOutTotal;

    // ============ Modifiers ============ //

    function _adjustQuoteTokenDecimals(uint96 amount_) internal view returns (uint96) {
        uint256 adjustedAmount = amount_ * 10 ** (_quoteToken.decimals()) / 1e18;

        if (adjustedAmount > type(uint96).max) revert("overflow");

        return uint96(adjustedAmount);
    }

    function _adjustBaseTokenDecimals(uint96 amount_) internal view returns (uint96) {
        uint256 adjustedAmount = amount_ * 10 ** (_baseToken.decimals()) / 1e18;

        if (adjustedAmount > type(uint96).max) revert("overflow");

        return uint96(adjustedAmount);
    }

    modifier givenBidsAreBelowMinimumFilled() {
        // Capacity: 1 + 1 < 2.5 minimum
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);

        // Marginal price: 0 (due to not meeting minimum)
        _marginalPrice = 0;

        // Output
        // Bid one: 0 out
        // Bid two: 0 out

        _bidAmountInTotal = _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT;
        _bidAmountOutTotal = _BID_PRICE_TWO_AMOUNT_OUT + _BID_PRICE_TWO_AMOUNT_OUT;
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

        _bidAmountInTotal = _BID_PRICE_ONE_AMOUNT + _BID_PRICE_ONE_AMOUNT + _BID_PRICE_ONE_AMOUNT;
        _bidAmountOutTotal =
            _BID_PRICE_ONE_AMOUNT_OUT + _BID_PRICE_ONE_AMOUNT_OUT + _BID_PRICE_ONE_AMOUNT_OUT;
        _;
    }

    modifier givenBidsAreAboveMinimumAndBelowCapacity() {
        // Capacity: 1 + 1 + 1 + 1 >= 2.5 minimum && < 10 capacity
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_AMOUNT, _BID_PRICE_TWO_AMOUNT_OUT);

        // Marginal price: 2 >= 2 (due to capacity not being reached and the last bid having a price of 2)
        _marginalPrice = 2e18;

        // Output
        // Bid one: 2 / 2 = 1 out
        // Bid two: 2 / 2 = 1 out
        // Bid three: 2 / 2 = 1 out
        // Bid four: 2 / 2 = 1 out

        _bidAmountInTotal = _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT + _BID_PRICE_TWO_AMOUNT
            + _BID_PRICE_TWO_AMOUNT;
        _bidAmountOutTotal = _BID_PRICE_TWO_AMOUNT_OUT + _BID_PRICE_TWO_AMOUNT_OUT
            + _BID_PRICE_TWO_AMOUNT_OUT + _BID_PRICE_TWO_AMOUNT_OUT;
        _;
    }

    modifier givenBidsAreOverSubscribed() {
        // Capacity: 9 + 2 > 10 capacity
        // Capacity reached on bid 2
        _createBid(_BID_SIZE_NINE_AMOUNT, _BID_SIZE_NINE_AMOUNT_OUT);
        _createBid(_BID_PRICE_TWO_SIZE_TWO_AMOUNT, _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT);

        // Marginal price: 2 >= 2 (due to capacity being reached on bid 2)
        _marginalPrice = 2e18;

        // Output
        // Bid one: 19 / 2 = 9.5 out
        // Bid two: 10 - 9.5 = 0.5 out (partial fill)

        _bidAmountInTotal = _BID_SIZE_NINE_AMOUNT + _BID_PRICE_TWO_SIZE_TWO_AMOUNT;
        _bidAmountOutTotal = _BID_SIZE_NINE_AMOUNT_OUT + _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT;
        _;
    }

    modifier givenBidsAreOverSubscribedRespectsOrdering() {
        // Capacity: 10 + 2 > 10 capacity
        // Capacity reached on bid 1 (which is processed second)
        _createBid(20e18, 10e18);
        _createBid(_BID_PRICE_TWO_SIZE_TWO_AMOUNT, _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT);

        // Marginal price: 2 >= 2 (due to capacity being reached on bid 1)
        _marginalPrice = 2e18;

        // Output
        // Bid two: 4 / 2 = 2 out
        // Bid one: 10 - 2 = 8 out (partial fill)

        _bidAmountInTotal = 20e18 + _BID_PRICE_TWO_SIZE_TWO_AMOUNT;
        _bidAmountOutTotal = 10e18 + _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT;
        _;
    }

    modifier givenBidsAreOverSubscribedOnFirstBid() {
        // Capacity: 11 > 10 capacity
        // Capacity reached on bid 1
        _createBid(22e18, 11e18);

        // Marginal price: 2 >= 2 (due to capacity being reached on bid 1)
        _marginalPrice = 2e18;

        // Output
        // Bid one: 10 out (partial fill)

        _bidAmountInTotal = 22e18;
        _bidAmountOutTotal = 11e18;
        _;
    }

    modifier givenSomeBidsAreBelowMinimumPrice() {
        // Capacity: 2 + 2 + 1 + 1 >= 2.5 minimum
        _createBid(_BID_PRICE_THREE_AMOUNT, _BID_PRICE_THREE_AMOUNT_OUT);
        _createBid(_BID_PRICE_THREE_AMOUNT, _BID_PRICE_THREE_AMOUNT_OUT);
        _createBid(_BID_PRICE_ONE_AMOUNT, _BID_PRICE_ONE_AMOUNT_OUT);
        _createBid(_BID_PRICE_ONE_AMOUNT, _BID_PRICE_ONE_AMOUNT_OUT);

        // Marginal price: 3 >= 2 (due to capacity not being reached and the last bid above the minimum having a price of 3)
        _marginalPrice = 3e18;

        // Output
        // Bid one: 6 / 3 = 2 out
        // Bid two: 6 / 3 = 2 out
        // Bid three: 0 out
        // Bid four: 0 out

        _bidAmountInTotal = _BID_PRICE_THREE_AMOUNT + _BID_PRICE_THREE_AMOUNT
            + _BID_PRICE_ONE_AMOUNT + _BID_PRICE_ONE_AMOUNT;
        _bidAmountOutTotal = _BID_PRICE_THREE_AMOUNT_OUT + _BID_PRICE_THREE_AMOUNT_OUT
            + _BID_PRICE_ONE_AMOUNT_OUT + _BID_PRICE_ONE_AMOUNT_OUT;
        _;
    }

    function _mulDivUp(uint96 mul1_, uint96 mul2_, uint96 div_) internal pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivUp(mul1_, mul2_, div_);
        if (product > type(uint96).max) revert("overflow");

        return uint96(product);
    }

    // ============ Tests ============ //

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
    // [ ] given the bid is below the minimum size
    //  [ ] it ignores
    // [ ] given the auction house has insufficient balance of the quote token
    //  [ ] it reverts
    // [ ] given the auction house has insufficient balance of the base token
    //  [ ] it reverts
    // [ ] given that the quote token decimals are larger than the base token decimals
    //  [ ] it succeeds
    // [ ] given that the quote token decimals are smaller than the base token decimals
    //  [ ] it succeeds
    // [X] it succeeds - auction owner receives quote tokens (minus fees), bidders receive base tokens and fees accrued

    function test_bidsLessThanMinimumFilled()
        external
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

        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house balance"
        );
        assertEq(_baseToken.balanceOf(_auctionOwner), _LOT_CAPACITY, "base token: owner balance"); // Unused capacity
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _bidAmountInTotal,
            "quote token: auction house balance"
        );
        assertEq(_quoteToken.balanceOf(_auctionOwner), 0, "quote token: owner balance");
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: bidder balance");
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function test_marginalPriceLessThanMinimum()
        external
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

        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house balance"
        );
        assertEq(_baseToken.balanceOf(_auctionOwner), _LOT_CAPACITY, "base token: owner balance"); // Unused capacity
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _bidAmountInTotal,
            "quote token: auction house balance"
        );
        assertEq(_quoteToken.balanceOf(_auctionOwner), 0, "quote token: owner balance");
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: bidder balance");
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function test_filledCapacityGreaterThanMinimum()
        external
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

        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _bidAmountOutTotal,
            "base token: auction house balance"
        ); // To be claimed by the bidder
        assertEq(
            _baseToken.balanceOf(_auctionOwner),
            _LOT_CAPACITY - _bidAmountOutTotal,
            "base token: owner balance"
        ); // Unused capacity
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)), 0, "quote token: auction house balance"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner), _bidAmountInTotal, "quote token: owner balance"
        );
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: bidder balance");
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function test_someBidsBelowMinimumPrice()
        external
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

        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _BID_PRICE_THREE_AMOUNT_OUT + _BID_PRICE_THREE_AMOUNT_OUT,
            "base token: auction house balance"
        ); // To be claimed by the bidder
        assertEq(
            _baseToken.balanceOf(_auctionOwner),
            _LOT_CAPACITY - _BID_PRICE_THREE_AMOUNT_OUT - _BID_PRICE_THREE_AMOUNT_OUT,
            "base token: owner balance"
        ); // Unused capacity
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _BID_PRICE_ONE_AMOUNT + _BID_PRICE_ONE_AMOUNT,
            "quote token: auction house balance"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _BID_PRICE_THREE_AMOUNT + _BID_PRICE_THREE_AMOUNT,
            "quote token: owner balance"
        );
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: bidder balance");
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function test_partialFill()
        external
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
            _quoteToken.balanceOf(address(_auctionHouse)), 0, "quote token: auction house balance"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            bidOneAmountInActual + bidTwoAmountInActual,
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

    function test_partialFill_ordering()
        external
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

        uint96 bidTwoAmountOutActual = _BID_PRICE_TWO_SIZE_TWO_AMOUNT_OUT; // 2
        uint96 bidTwoAmountInActual = _BID_PRICE_TWO_SIZE_TWO_AMOUNT; // 4
        uint96 bidOneAmountOutActual = _LOT_CAPACITY - bidTwoAmountOutActual; // 8
        uint96 bidOneAmountInActual = _mulDivUp(bidOneAmountOutActual, 20e18, 10e18); // 8 * 20 / 10 = 16

        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            bidTwoAmountOutActual,
            "base token: auction house balance"
        ); // To be claimed by the bidder
        assertEq(_baseToken.balanceOf(_auctionOwner), 0, "base token: owner balance"); // No unused capacity
        assertEq(_baseToken.balanceOf(_bidder), bidOneAmountOutActual, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)), 0, "quote token: auction house balance"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            bidOneAmountInActual + bidTwoAmountInActual,
            "quote token: owner balance"
        );
        assertEq(
            _quoteToken.balanceOf(_bidder),
            20e18 - bidOneAmountInActual,
            "quote token: bidder balance"
        );
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function test_singleBid_partialFill()
        external
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

        uint96 bidOneAmountOutActual = _LOT_CAPACITY;
        uint96 bidOneAmountInActual = _mulDivUp(bidOneAmountOutActual, 22e18, 11e18);

        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house balance"
        ); // Nothing to be claimed
        assertEq(_baseToken.balanceOf(_auctionOwner), 0, "base token: owner balance"); // No unused capacity
        assertEq(_baseToken.balanceOf(_bidder), bidOneAmountOutActual, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)), 0, "quote token: auction house balance"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner), bidOneAmountInActual, "quote token: owner balance"
        );
        assertEq(
            _quoteToken.balanceOf(_bidder),
            22e18 - bidOneAmountInActual,
            "quote token: bidder balance"
        );
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    // [ ] given that the referrer fee is set
    //  [ ] the referrer fee is accrued, referrer fee is deducted from payment

    // [ ] given that the protocol fee is set
    //  [ ] the protocol fee is accrued, protocol fee is deducted from payment
    //  [ ] given that the referrer fee is set
    //   [ ] the protocol and referrer fee are accrued, both fees deducted from payment

    // [ ] given there is a curator set
    //  [ ] given the payout token is a derivative
    //   [ ] derivative is minted and transferred to the curator
    //  [ ] payout token is transferred to the curator
}
