// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";

import {BatchAuctionHouseTest} from "test/BatchAuctionHouse/AuctionHouseTest.sol";

contract BatchSettleTest is BatchAuctionHouseTest {
    uint256 internal constant _BID_AMOUNT_TOTAL = 20e18;

    uint256 internal _expectedAuctionHouseQuoteTokenBalance;

    uint256 internal _expectedAuctionHouseBaseTokenBalance;

    uint256 internal _expectedDerivativeBaseTokenBalance;
    uint256 internal _expectedCuratorBaseTokenRewards;
    bool internal _lotSettles;

    // ======== Modifiers ======== //

    function _assertBaseTokenBalances() internal {
        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _expectedAuctionHouseBaseTokenBalance,
            "base token: auction house balance"
        );
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance");
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");
        assertEq(
            _baseToken.balanceOf(address(_derivativeModule)),
            _expectedDerivativeBaseTokenBalance,
            "base token: derivative balance"
        );

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _expectedAuctionHouseBaseTokenBalance, "funding");
    }

    function _assertQuoteTokenBalances() internal {
        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _expectedAuctionHouseQuoteTokenBalance,
            "quote token: auction house balance"
        );
        assertEq(_quoteToken.balanceOf(_SELLER), 0, "quote token: seller balance");
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: bidder balance");
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function _assertAccruedFees() internal {
        // Check accrued quote token fees have not yet been set
        assertEq(_auctionHouse.rewards(_REFERRER, _quoteToken), 0, "referrer fee");
        assertEq(_auctionHouse.rewards(_CURATOR, _quoteToken), 0, "curator fee"); // Always 0
        assertEq(_auctionHouse.rewards(_PROTOCOL, _quoteToken), 0, "protocol fee");
    }

    function _mockSettlement(
        uint256 totalIn_,
        uint256 totalOut_,
        bytes memory auctionOutput_
    ) internal {
        vm.mockCall(
            address(_auctionModule),
            abi.encodeWithSelector(BatchAuctionModule.settle.selector, _lotId),
            abi.encode(totalIn_, totalOut_, auctionOutput_)
        );
    }

    modifier givenAuctionModuleReverts() {
        vm.mockCallRevert(
            address(_auctionModule),
            abi.encodeWithSelector(BatchAuctionModule.settle.selector, _lotId),
            "revert"
        );
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

        _mockSettlement(totalInFilled, totalOut, "");

        // Calculate fees
        uint256 prefundedCuratorFees =
            _curatorApproved ? _scaleBaseTokenAmount(_curatorMaxPotentialFee) : 0;

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = totalIn; // To be claimed by seller

        // Base token
        _expectedAuctionHouseBaseTokenBalance = scaledLotCapacity + prefundedCuratorFees; // Entire capacity and potential curator fees are kept in the AuctionHouse

        _lotSettles = true;
        _;
    }

    modifier givenLotIsUnderCapacity() {
        uint256 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint256 totalOut = _scaleBaseTokenAmount(5e18); // 50% filled
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _mockSettlement(totalIn, totalOut, "");

        // Calculate fees
        uint256 prefundedCuratorFees =
            _curatorApproved ? _scaleBaseTokenAmount(_curatorMaxPotentialFee) : 0;

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = totalIn;

        // Base token
        _expectedAuctionHouseBaseTokenBalance = scaledLotCapacity + prefundedCuratorFees; // To be claimed by bidders, seller, and curator

        _lotSettles = true;
        _;
    }

    modifier givenLotCapacityIsFilled() {
        uint256 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint256 totalOut = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _mockSettlement(totalIn, totalOut, "");

        // Calculate fees
        uint256 prefundedCuratorFees =
            _curatorApproved ? _scaleBaseTokenAmount(_curatorMaxPotentialFee) : 0;

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = totalIn;

        // Base token
        _expectedAuctionHouseBaseTokenBalance = scaledLotCapacity + prefundedCuratorFees; // To be claimed by bidders, seller, and curator

        _lotSettles = true;
        _;
    }

    modifier givenLotDoesNotSettle() {
        uint256 totalIn = 0;
        uint256 totalOut = 0;
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _mockSettlement(totalIn, totalOut, "");

        // Calculate fees
        uint256 prefundedCuratorFees =
            _curatorApproved ? _scaleBaseTokenAmount(_curatorMaxPotentialFee) : 0;

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL); // To be claimed by bidders

        // Base token
        _expectedAuctionHouseBaseTokenBalance = scaledLotCapacity + prefundedCuratorFees; // To be claimed by seller

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
    //   [X] it does not transfer the capacity and curator fee to the seller
    //  [X] it does not transfer the capacity to the seller
    // [X] when there is a partial fill
    //  [X] it completes settlement
    // [X] when capacity is not filled
    //  [X] when curated is true
    //   [X] it completes settlement
    // [X] when curated is true
    //  [X] it completes settlement
    // [X] it completes settlement

    function test_whenLotIdIsInvalid_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidLotId.selector, _lotId);
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
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
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_curated_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_curated_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_curated_curatorFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_protocolFeeNotSet_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_protocolFeeNotSet_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_referrerFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_referrerFeeNotSet_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_referrerFeeNotSet_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
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

    function test_capacityFilled_protocolFeeNotSet_referrerFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
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
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
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
