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

    bool internal _lotSettles;

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

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _expectedAuctionHouseBaseTokenBalance, "funding");
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
        // Check that the protocol and referrer fees have been cached
        Auctioneer.FeeData memory feeData = _getLotFees(_lotId);
        assertEq(feeData.protocolFee, _lotSettles ? _protocolFeePercentActual : 0, "protocol fee");
        assertEq(feeData.referrerFee, _lotSettles ? _referrerFeePercentActual : 0, "referrer fee");

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

    modifier givenLotHasPartialFill() {
        uint96 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint96 totalOut = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        // Total bid was 4e18, since 2e18 of quote token = 1e18 of base token
        uint96 pfRefundAmount = _scaleQuoteTokenAmount(2e18);
        uint96 pfPayoutAmount = _scaleBaseTokenAmount(1e18);
        uint96 pfFilledAmount = _scaleQuoteTokenAmount(4e18) - pfRefundAmount;
        uint96 totalInFilled = totalIn - pfRefundAmount;

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
        _expectedSellerQuoteTokenBalance = 0; // To be claimed by seller
        _expectedBidderQuoteTokenBalance = pfRefundAmount;
        _expectedAuctionHouseQuoteTokenBalance = totalIn - pfRefundAmount;
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
            scaledLotCapacity + prefundedCuratorFees - pfPayoutAmount - totalCuratorFees; // Entire capacity and potential curator fees are kept in the auctionhouse (regardless of prefunding)
        _expectedCuratorBaseTokenBalance = totalCuratorFees;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance,
            scaledLotCapacity + prefundedCuratorFees,
            "total base token balance mismatch"
        );

        _lotSettles = true;
        _;
    }

    modifier givenLotIsUnderCapacity() {
        uint96 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint96 totalOut = _scaleBaseTokenAmount(5e18); // 50% filled
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
        _expectedSellerQuoteTokenBalance = 0; // To be claimed by seller
        _expectedBidderQuoteTokenBalance = 0;
        _expectedAuctionHouseQuoteTokenBalance = totalIn;
        assertEq(
            _expectedSellerQuoteTokenBalance + _expectedBidderQuoteTokenBalance
                + _expectedAuctionHouseQuoteTokenBalance,
            totalIn,
            "total quote token balance mismatch"
        );

        // Base token
        _expectedSellerBaseTokenBalance = 0; // To be claimed by seller
        _expectedBidderBaseTokenBalance = 0; // To be claimed by bidder
        _expectedAuctionHouseBaseTokenBalance =
            scaledLotCapacity + prefundedCuratorFees - totalCuratorFees; // Entire capacity and potential curator fees are kept in the auctionhouse (regardless of prefunding)
        _expectedCuratorBaseTokenBalance = totalCuratorFees;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance,
            scaledLotCapacity + prefundedCuratorFees,
            "total base token balance mismatch"
        );

        _lotSettles = true;
        _;
    }

    modifier givenLotCapacityIsFilled() {
        uint96 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint96 totalOut = _scaleBaseTokenAmount(_LOT_CAPACITY);
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
        _expectedSellerQuoteTokenBalance = 0; // To be claimed by seller
        _expectedBidderQuoteTokenBalance = 0;
        _expectedAuctionHouseQuoteTokenBalance = totalIn;
        assertEq(
            _expectedSellerQuoteTokenBalance + _expectedBidderQuoteTokenBalance
                + _expectedAuctionHouseQuoteTokenBalance,
            totalIn,
            "total quote token balance mismatch"
        );

        // Base token
        _expectedSellerBaseTokenBalance = 0; // To be claimed by seller
        _expectedBidderBaseTokenBalance = 0; // To be claimed by bidder
        _expectedAuctionHouseBaseTokenBalance =
            scaledLotCapacity + prefundedCuratorFees - totalCuratorFees; // To be claimed by bidders and seller
        _expectedCuratorBaseTokenBalance = totalCuratorFees;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance,
            scaledLotCapacity + prefundedCuratorFees,
            "total base token balance mismatch"
        );

        _lotSettles = true;
        _;
    }

    modifier givenLotDoesNotSettle() {
        uint96 totalIn = 0;
        uint96 totalOut = 0;
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

        bool isPrefunded = _routingParams.prefunded;

        // Set up expected values
        // Quote token
        _expectedSellerQuoteTokenBalance = 0; // To be claimed by seller
        _expectedBidderQuoteTokenBalance = 0; // To be claimed by bidder
        _expectedAuctionHouseQuoteTokenBalance = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL); // To be claimed by bidders
        assertEq(
            _expectedSellerQuoteTokenBalance + _expectedBidderQuoteTokenBalance
                + _expectedAuctionHouseQuoteTokenBalance,
            _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL),
            "total quote token balance mismatch"
        );

        // Base token
        _expectedSellerBaseTokenBalance = isPrefunded ? 0 : scaledLotCapacity + prefundedCuratorFees;
        _expectedBidderBaseTokenBalance = 0;
        _expectedAuctionHouseBaseTokenBalance =
            isPrefunded ? scaledLotCapacity + prefundedCuratorFees : 0; // To be claimed by seller
        _expectedCuratorBaseTokenBalance = 0;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance,
            scaledLotCapacity + prefundedCuratorFees,
            "total base token balance mismatch"
        );

        _lotSettles = false;
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
    //  [X] it allocates fees, updates funding, transfers the partial payment and refund to the bidder, transfers the payment to the seller, and allocates fees to the curator
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
    // [X] when the curator fee is changed before settlement
    //  [X] it sends the curator payout using the original curator fee
    // [X] it caches the protocol and referrer fees

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

    function test_notSettled_curated_curatorFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
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

    function test_notSettled_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
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

    function test_partialFill_curated_curatorFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
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

    function test_partialFill_curated_givenCuratorFeeIsChanged()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
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
        // Change curator fee
        _setCuratorFee(80);

        // Call function
        _auctionHouse.settle(_lotId);

        // Check balances
        // Assertions are not updated with the curator fee, so the test will fail if the new curator fee is used by the AuctionHouse
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
    }

    function test_partialFill_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
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

    function test_underCapacity_curated_curatorFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
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

    function test_underCapacity_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
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

    function test_capacityFilled_curated_curatorFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
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

    function test_capacityFilled_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
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
}
