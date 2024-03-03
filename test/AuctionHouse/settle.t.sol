// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction, AuctionModule} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract SettleTest is AuctionHouseTest {
    uint96 internal constant _BID_AMOUNT_TOTAL = 20e18;

    uint256 internal _expectedSellerQuoteTokenBalance;
    uint256 internal _expectedBidderQuoteTokenBalance;
    uint256 internal _expectedAuctionHouseQuoteTokenBalance;

    uint256 internal _expectedSellerBaseTokenBalance;
    uint256 internal _expectedBidderBaseTokenBalance;
    uint256 internal _expectedAuctionHouseBaseTokenBalance;
    uint256 internal _expectedCuratorBaseTokenBalance;

    uint256 internal _expectedProtocolFeesAllocated;
    uint256 internal _expectedReferrerFeesAllocated;

    // ======== Modifiers ======== //

    function _assertBaseTokenBalances() internal {
        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _expectedAuctionHouseBaseTokenBalance,
            "base token: auction house balance"
        );
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _expectedSellerBaseTokenBalance,
            "base token: seller balance"
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
            _quoteToken.balanceOf(_SELLER),
            _expectedSellerQuoteTokenBalance,
            "quote token: seller balance"
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
            _expectedReferrerFeesAllocated,
            "referrer fee"
        );
        assertEq(_auctionHouse.rewards(_CURATOR, _quoteToken), 0, "curator fee"); // Always 0
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            _expectedProtocolFeesAllocated,
            "protocol fee"
        );
    }

    function _mockSettlement(
        Auction.Settlement memory settlement_,
        bytes memory auctionOutput_
    ) internal {
        vm.mockCall(
            address(_auctionModule),
            abi.encodeWithSelector(AuctionModule.settle.selector, _lotId),
            abi.encode(settlement_, auctionOutput_)
        );
    }

    modifier givenAuctionModuleReverts() {
        vm.mockCallRevert(
            address(_auctionModule),
            abi.encodeWithSelector(AuctionModule.settle.selector, _lotId),
            "revert"
        );
        _;
    }

    modifier givenLotIsPrefunded() {
        _batchAuctionModule.setRequiredPrefunding(true);
        _;
    }

    modifier givenLotHasPartialFill() {
        uint256 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint256 totalOut = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        // Total bid was 4e18, since 2e18 of quote token = 1e18 of base token
        uint256 pfRefundAmount = _scaleQuoteTokenAmount(2e18);
        uint256 pfPayoutAmount = _scaleBaseTokenAmount(1e18);
        uint256 pfFilledAmount = _scaleQuoteTokenAmount(4e18) - pfRefundAmount;
        uint256 totalInFilled = totalIn - pfRefundAmount;

        Auction.Settlement memory settlement = Auction.Settlement({
            totalIn: totalIn,
            totalOut: totalOut,
            pfBidder: _bidder,
            pfReferrer: _REFERRER,
            pfRefund: pfRefundAmount,
            pfPayout: pfPayoutAmount,
            auctionOutput: ""
        });
        _mockSettlement(settlement, "");

        // Calculate fees
        uint256 totalProtocolFees = (totalInFilled * _protocolFeePercentActual) / 1e5;
        uint256 totalReferrerFees = (totalInFilled * _referrerFeePercentActual) / 1e5;
        uint256 totalCuratorFees =
            _curatorApproved ? (totalOut * _curatorFeePercentActual) / 1e5 : 0;
        uint256 prefundedCuratorFees =
            _curatorApproved ? _scaleBaseTokenAmount(_curatorMaxPotentialFee) : 0;
        _expectedProtocolFeesAllocated = (pfFilledAmount * _protocolFeePercentActual) / 1e5;
        _expectedReferrerFeesAllocated = (pfFilledAmount * _referrerFeePercentActual) / 1e5;

        // Set up expected values
        // Quote token
        _expectedSellerQuoteTokenBalance =
            totalIn - totalProtocolFees - totalReferrerFees - pfRefundAmount;
        _expectedBidderQuoteTokenBalance = pfRefundAmount;
        _expectedAuctionHouseQuoteTokenBalance = totalProtocolFees + totalReferrerFees;
        assertEq(
            _expectedSellerQuoteTokenBalance + _expectedBidderQuoteTokenBalance
                + _expectedAuctionHouseQuoteTokenBalance,
            totalIn,
            "total quote token balance mismatch"
        );

        // Base token
        _expectedSellerBaseTokenBalance = 0;
        _expectedBidderBaseTokenBalance = pfPayoutAmount;
        _expectedAuctionHouseBaseTokenBalance =
            scaledLotCapacity + prefundedCuratorFees - pfPayoutAmount - totalCuratorFees;
        _expectedCuratorBaseTokenBalance = totalCuratorFees;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance,
            scaledLotCapacity + prefundedCuratorFees,
            "total base token balance mismatch"
        );
        _;
    }

    modifier givenLotIsUnderCapacity() {
        uint256 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint256 totalOut = _scaleBaseTokenAmount(5e18); // 50% filled
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        Auction.Settlement memory settlement = Auction.Settlement({
            totalIn: totalIn,
            totalOut: totalOut,
            pfBidder: address(0),
            pfReferrer: address(0),
            pfRefund: 0,
            pfPayout: 0,
            auctionOutput: ""
        });
        _mockSettlement(settlement, "");

        // Calculate fees
        uint256 totalProtocolFees = (totalIn * _protocolFeePercentActual) / 1e5;
        uint256 totalReferrerFees = (totalIn * _referrerFeePercentActual) / 1e5;
        uint256 totalCuratorFees =
            _curatorApproved ? (totalOut * _curatorFeePercentActual) / 1e5 : 0;
        uint256 prefundedCuratorFees =
            _curatorApproved ? _scaleBaseTokenAmount(_curatorMaxPotentialFee) : 0;
        _expectedProtocolFeesAllocated = 0; // Will be allocated at claim time
        _expectedReferrerFeesAllocated = 0; // Will be allocated at claim time

        // Set up expected values
        // Quote token
        _expectedSellerQuoteTokenBalance = totalIn - totalProtocolFees - totalReferrerFees;
        _expectedBidderQuoteTokenBalance = 0;
        _expectedAuctionHouseQuoteTokenBalance = totalProtocolFees + totalReferrerFees;
        assertEq(
            _expectedSellerQuoteTokenBalance + _expectedBidderQuoteTokenBalance
                + _expectedAuctionHouseQuoteTokenBalance,
            totalIn,
            "total quote token balance mismatch"
        );

        // Base token
        _expectedSellerBaseTokenBalance =
            scaledLotCapacity + prefundedCuratorFees - totalOut - totalCuratorFees; // Capacity and unused curator fees returned to seller
        _expectedBidderBaseTokenBalance = 0; // To be claimed by bidder
        _expectedAuctionHouseBaseTokenBalance = totalOut; // To be claimed by bidders
        _expectedCuratorBaseTokenBalance = totalCuratorFees;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance,
            scaledLotCapacity + prefundedCuratorFees,
            "total base token balance mismatch"
        );
        _;
    }

    modifier givenLotCapacityIsFilled() {
        uint256 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint256 totalOut = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        Auction.Settlement memory settlement = Auction.Settlement({
            totalIn: totalIn,
            totalOut: totalOut,
            pfBidder: address(0),
            pfReferrer: address(0),
            pfRefund: 0,
            pfPayout: 0,
            auctionOutput: ""
        });
        _mockSettlement(settlement, "");

        // Calculate fees
        uint256 totalProtocolFees = (totalIn * _protocolFeePercentActual) / 1e5;
        uint256 totalReferrerFees = (totalIn * _referrerFeePercentActual) / 1e5;
        uint256 totalCuratorFees =
            _curatorApproved ? (totalOut * _curatorFeePercentActual) / 1e5 : 0;
        uint256 prefundedCuratorFees =
            _curatorApproved ? _scaleBaseTokenAmount(_curatorMaxPotentialFee) : 0;
        _expectedProtocolFeesAllocated = 0; // Will be allocated at claim time
        _expectedReferrerFeesAllocated = 0; // Will be allocated at claim time

        // Set up expected values
        // Quote token
        _expectedSellerQuoteTokenBalance = totalIn - totalProtocolFees - totalReferrerFees;
        _expectedBidderQuoteTokenBalance = 0;
        _expectedAuctionHouseQuoteTokenBalance = totalProtocolFees + totalReferrerFees;
        assertEq(
            _expectedSellerQuoteTokenBalance + _expectedBidderQuoteTokenBalance
                + _expectedAuctionHouseQuoteTokenBalance,
            totalIn,
            "total quote token balance mismatch"
        );

        // Base token
        _expectedSellerBaseTokenBalance = 0; // Unused curator fees returned to seller
        _expectedBidderBaseTokenBalance = 0; // To be claimed by bidder
        _expectedAuctionHouseBaseTokenBalance = scaledLotCapacity; // To be claimed by bidders
        _expectedCuratorBaseTokenBalance = totalCuratorFees;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance,
            scaledLotCapacity + prefundedCuratorFees,
            "total base token balance mismatch"
        );
        _;
    }

    modifier givenLotDoesNotSettle() {
        uint256 totalIn = 0;
        uint256 totalOut = 0;
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        Auction.Settlement memory settlement = Auction.Settlement({
            totalIn: totalIn,
            totalOut: totalOut,
            pfBidder: address(0),
            pfReferrer: address(0),
            pfRefund: 0,
            pfPayout: 0,
            auctionOutput: ""
        });
        _mockSettlement(settlement, "");

        // Calculate fees
        uint256 totalProtocolFees = 0;
        uint256 totalReferrerFees = 0;
        uint256 totalCuratorFees = 0;
        uint256 prefundedCuratorFees =
            _curatorApproved ? _scaleBaseTokenAmount(_curatorMaxPotentialFee) : 0;
        _expectedProtocolFeesAllocated = 0;
        _expectedReferrerFeesAllocated = 0;

        // Set up expected values
        // Quote token
        _expectedSellerQuoteTokenBalance = 0; // Did not settle, no payment
        _expectedBidderQuoteTokenBalance = 0; // To be claimed
        _expectedAuctionHouseQuoteTokenBalance = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL); // To be claimed by bidders
        assertEq(
            _expectedSellerQuoteTokenBalance + _expectedBidderQuoteTokenBalance
                + _expectedAuctionHouseQuoteTokenBalance,
            _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL),
            "total quote token balance mismatch"
        );

        // Base token
        _expectedSellerBaseTokenBalance = scaledLotCapacity + prefundedCuratorFees;
        _expectedBidderBaseTokenBalance = 0;
        _expectedAuctionHouseBaseTokenBalance = 0; // Refunded to seller
        _expectedCuratorBaseTokenBalance = 0;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance,
            scaledLotCapacity + prefundedCuratorFees,
            "total base token balance mismatch"
        );
        _;
    }

    modifier givenAuctionHouseHasQuoteTokenBalance(uint256 amount_) {
        _quoteToken.mint(address(_auctionHouse), amount_);
        _;
    }

    // ======== Tests ======== //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction module reverts
    //  [X] it reverts
    // [X] when the auction does not settle
    //  [X] when curated is true
    //   [X] it transfers the capacity and curator fee to the seller
    //  [X] it transfer the capacity to the seller
    // [X] when there is a partial fill
    //  [X] it allocates fees, updates prefunding, transfers the partial payment and refund to the bidder, transfers the payment to the seller, and allocates fees to the curator
    // [X] when capacity is not filled
    //  [X] when curated is true
    //   [X] it transfers the remaining capacity back to the seller, and pays the curator fee based on the utilised capacity
    //  [X] it transfers the remaining capacity back to the seller
    // [X] when protocol fees are not set
    //  [X] it transfers the entire payment - referrer fees to the seller
    // [X] when referrer fees are not set
    //  [X] it transfers the entire payment - protocol fees to the seller
    // [X] when protocol and referrer fees are not set
    //  [X] it transfers the entire payment to the seller
    // [X] when curated is true
    //  [X] it transfers the curator fee to the curator
    // [X] it transfers the payment (minus protocol and referrer fees) to the seller
    // [X] when prefunding is disabled
    //  [X] when the auction is not settled
    //   [X] it does not transfer any base tokens to the auction house
    //  [X] when there is a partial fill
    //   [X] when curated is true
    //    [X] it transfers the capacity and curator fee to the auction house
    //   [X] it transfers the capacity to the auction house
    //  [X] when capacity is not filled
    //   [X] when curated is true
    //    [X] it transfers the used capacity and curator fee to the auction house
    //   [X] it transfers the used capacity to the auction house
    // [ ] when the curator fee is changed before settlement
    //  [ ] it sends the curator payout using the original curator fee
    // [ ] it caches the protocol and referrer fees

    // TODO modify tests to assert that the seller payout and unused capacity is not sent to the seller

    function test_whenLotIdIsInvalid_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    function test_whenAuctionModuleReverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenAuctionModuleReverts
    {
        // Expect revert
        vm.expectRevert("revert");

        // Call function
        _auctionHouse.settle(_lotId);
    }

    // ======== prefunded ======== //

    function test_notSettled_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notSettled_curated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notSettled_curated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notSettled_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notSettled_notCurated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notSettled_notCurated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_curated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_curated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_notCurated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_notCurated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_underCapacity_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_underCapacity_curated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_underCapacity_curated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_underCapacity_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_underCapacity_notCurated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_underCapacity_notCurated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_curated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_curated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_notCurated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_notCurated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_protocolFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_protocolFeeNotSet_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_protocolFeeNotSet_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenReferrerFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_referrerFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_referrerFeeNotSet_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_referrerFeeNotSet_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_protocolFeeNotSet_referrerFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_protocolFeeNotSet_referrerFeeNotSet_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_capacityFilled_protocolFeeNotSet_referrerFeeNotSet_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    // ======== not prefunded ======== //

    function test_notPrefunded_notSettled_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_notSettled_curated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_notSettled_curated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_notSettled_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_notSettled_notCurated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_notSettled_notCurated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotDoesNotSettle
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_partialFill_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_partialFill_curated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_partialFill_curated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_partialFill_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_partialFill_notCurated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_partialFill_notCurated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasPartialFill
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_underCapacity_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY + _curatorMaxPotentialFee)
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_underCapacity_curated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_underCapacity_curated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY + _curatorMaxPotentialFee))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_underCapacity_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_underCapacity_notCurated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_notPrefunded_underCapacity_notCurated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsUnderCapacity
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }
}
