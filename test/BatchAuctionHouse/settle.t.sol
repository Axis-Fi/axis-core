// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuctionHouse} from "../../src/interfaces/IAuctionHouse.sol";
import {BatchAuctionModule} from "../../src/modules/auctions/BatchAuctionModule.sol";

import {MockBatchAuctionModule} from "../modules/Auction/MockBatchAuctionModule.sol";
import {BatchAuctionHouseTest} from "./AuctionHouseTest.sol";

contract BatchSettleTest is BatchAuctionHouseTest {
    uint256 internal constant _BID_AMOUNT_TOTAL = 20e18;
    uint256 internal constant _SETTLE_BATCH_SIZE = 100_000;

    bytes internal constant _ON_SETTLE_CALLBACK_PARAMS = "";

    uint256 internal _expectedAuctionHouseQuoteTokenBalance;
    uint256 internal _expectedSellerQuoteTokenBalance;
    uint256 internal _expectedCallbackQuoteTokenBalance;

    uint256 internal _expectedAuctionHouseBaseTokenBalance;
    uint256 internal _expectedSellerBaseTokenBalance;
    uint256 internal _expectedCallbackBaseTokenBalance;

    uint256 internal _expectedCuratorBaseTokenRewards;

    bool internal _lotSettles;
    bool internal _lotSettlementFinished;

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
            _baseToken.balanceOf(address(_callback)),
            _expectedCallbackBaseTokenBalance,
            "base token: callback balance"
        );
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            lotRouting.funding,
            _expectedAuctionHouseBaseTokenBalance - _expectedCuratorBaseTokenRewards,
            "funding"
        ); // Curator fee has been allocated and is removed from the funding amount
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
            _quoteToken.balanceOf(address(_callback)),
            _expectedCallbackQuoteTokenBalance,
            "quote token: callback balance"
        );
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: bidder balance");
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function _assertAccruedFees() internal {
        // Check accrued quote token fees have not yet been set
        assertEq(_auctionHouse.rewards(_REFERRER, _quoteToken), 0, "quote token: referrer fee");
        assertEq(_auctionHouse.rewards(_PROTOCOL, _quoteToken), 0, "quote token: protocol fee");
        assertEq(_auctionHouse.rewards(_CURATOR, _quoteToken), 0, "quote token: curator fee");

        // Check base token fees
        assertEq(_auctionHouse.rewards(_REFERRER, _baseToken), 0, "base token: referrer fee");
        assertEq(_auctionHouse.rewards(_PROTOCOL, _baseToken), 0, "base token: protocol fee");
        assertEq(
            _auctionHouse.rewards(_CURATOR, _baseToken),
            _expectedCuratorBaseTokenRewards,
            "base token: curator fee"
        );
    }

    function _assertState() internal {
        // Check the lot status
        assertEq(
            uint8(_batchAuctionModule.lotStatus(_lotId)),
            _lotSettlementFinished
                ? uint8(MockBatchAuctionModule.LotStatus.Settled)
                : uint8(MockBatchAuctionModule.LotStatus.Created),
            "lot status"
        );

        // Check callback state if set
        if (address(_routingParams.callbacks) != address(0)) {
            assertEq(
                _callback.lotSettled(_lotId), _lotSettlementFinished, "callback: onSettle called"
            );
        }
    }

    function _assertLotSettlementOutput(uint256, uint256, bool finished_, bytes memory) internal {
        assertEq(finished_, _lotSettlementFinished, "finished");
    }

    function _mockSettlement(
        uint256 totalIn_,
        uint256 totalOut_,
        bool finished_,
        bytes memory
    ) internal {
        _batchAuctionModule.setLotSettlement(_lotId, totalIn_, totalOut_, finished_);
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

        _concludeLot();

        _lotSettlementFinished = true;
        _mockSettlement(totalInFilled, totalOut, _lotSettlementFinished, "");

        // Calculate fees
        uint256 prefundedCuratorFees = _curatorApproved ? _curatorMaxPotentialFee : 0;
        uint256 curatorPayout = _calculateCuratorFee(totalOut);
        (,, uint256 totalQuoteTokenFees) = _calculateFees(_REFERRER, totalInFilled);

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = pfRefundAmount + totalQuoteTokenFees; // To be claimed by bidder + rewards
        _expectedSellerQuoteTokenBalance =
            _callbackReceiveQuoteTokens ? 0 : totalInFilled - totalQuoteTokenFees; // Transferred to seller if callback doesn't receive quote tokens
        _expectedCallbackQuoteTokenBalance =
            _callbackReceiveQuoteTokens ? totalInFilled - totalQuoteTokenFees : 0; // Transferred to callback if it receives quote tokens

        // Base token
        _expectedAuctionHouseBaseTokenBalance = scaledLotCapacity + curatorPayout; // To be claimed be bidders and curator
        _expectedSellerBaseTokenBalance =
            _callbackSendBaseTokens ? 0 : prefundedCuratorFees - curatorPayout; // Transferred to seller if callback doesn't send base tokens
        _expectedCallbackBaseTokenBalance =
            _callbackSendBaseTokens ? prefundedCuratorFees - curatorPayout : 0; // Transferred to callback if it sends base tokens

        _expectedCuratorBaseTokenRewards = curatorPayout;

        _lotSettles = true;
        _;
    }

    modifier givenLotIsUnderCapacity() {
        uint256 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint256 totalOut = _scaleBaseTokenAmount(5e18); // 50% filled
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _concludeLot();

        _lotSettlementFinished = true;
        _mockSettlement(totalIn, totalOut, _lotSettlementFinished, "");

        // Calculate fees
        uint256 prefundedCuratorFees = _curatorApproved ? _curatorMaxPotentialFee : 0;
        uint256 curatorPayout = _calculateCuratorFee(totalOut);
        (,, uint256 totalQuoteTokenFees) = _calculateFees(_REFERRER, totalIn);

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = totalQuoteTokenFees; // Rewards
        _expectedSellerQuoteTokenBalance =
            _callbackReceiveQuoteTokens ? 0 : totalIn - totalQuoteTokenFees; // Transferred to seller if callback doesn't receive quote tokens
        _expectedCallbackQuoteTokenBalance =
            _callbackReceiveQuoteTokens ? totalIn - totalQuoteTokenFees : 0; // Transferred to callback if it receives quote tokens

        // Base token
        _expectedAuctionHouseBaseTokenBalance = totalOut + curatorPayout; // To be claimed be bidders and curator
        _expectedSellerBaseTokenBalance = _callbackSendBaseTokens
            ? 0
            : scaledLotCapacity - totalOut + prefundedCuratorFees - curatorPayout; // Transferred to seller if callback doesn't send base tokens
        _expectedCallbackBaseTokenBalance = _callbackSendBaseTokens
            ? scaledLotCapacity - totalOut + prefundedCuratorFees - curatorPayout
            : 0; // Transferred to callback if it sends base tokens

        _expectedCuratorBaseTokenRewards = curatorPayout;

        _lotSettles = true;
        _;
    }

    modifier givenLotCapacityIsFilled() {
        uint256 totalIn = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL);
        uint256 totalOut = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _concludeLot();

        _lotSettlementFinished = true;
        _mockSettlement(totalIn, totalOut, _lotSettlementFinished, "");

        // Calculate fees
        uint256 prefundedCuratorFees = _curatorApproved ? _curatorMaxPotentialFee : 0;
        uint256 curatorPayout = _calculateCuratorFee(totalOut);
        (,, uint256 totalQuoteTokenFees) = _calculateFees(_REFERRER, totalIn);

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = totalQuoteTokenFees; // Rewards
        _expectedSellerQuoteTokenBalance =
            _callbackReceiveQuoteTokens ? 0 : totalIn - totalQuoteTokenFees; // Transferred to seller if callback doesn't receive quote tokens
        _expectedCallbackQuoteTokenBalance =
            _callbackReceiveQuoteTokens ? totalIn - totalQuoteTokenFees : 0; // Transferred to callback if it receives quote tokens

        // Base token
        _expectedAuctionHouseBaseTokenBalance = totalOut + curatorPayout; // To be claimed be bidders and curator
        _expectedSellerBaseTokenBalance = _callbackSendBaseTokens
            ? 0
            : scaledLotCapacity - totalOut + prefundedCuratorFees - curatorPayout; // Transferred to seller if callback doesn't send base tokens
        _expectedCallbackBaseTokenBalance = _callbackSendBaseTokens
            ? scaledLotCapacity - totalOut + prefundedCuratorFees - curatorPayout
            : 0; // Transferred to callback if it sends base tokens

        _expectedCuratorBaseTokenRewards = curatorPayout;

        _lotSettles = true;
        _;
    }

    modifier givenLotDoesNotSettle() {
        uint256 totalIn = 0;
        uint256 totalOut = 0;
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _concludeLot();

        _lotSettlementFinished = true;
        _mockSettlement(totalIn, totalOut, _lotSettlementFinished, "");

        // Calculate fees
        uint256 prefundedCuratorFees = _curatorApproved ? _curatorMaxPotentialFee : 0;
        uint256 curatorPayout = _calculateCuratorFee(totalOut);
        (,, uint256 totalQuoteTokenFees) = _calculateFees(_REFERRER, totalIn);

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL); // To be claimed by bidders
        _expectedSellerQuoteTokenBalance = 0; // Nothing transferred

        // Base token
        _expectedAuctionHouseBaseTokenBalance = 0;
        _expectedSellerBaseTokenBalance = scaledLotCapacity + prefundedCuratorFees; // Refunded to seller

        _expectedCuratorBaseTokenRewards = 0; // No curator fees allocated

        _lotSettles = false;
        _;
    }

    modifier givenLotSettlementNotFinished() {
        uint256 totalIn = 0;
        uint256 totalOut = 0;
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _concludeLot();

        _lotSettlementFinished = false;
        _mockSettlement(totalIn, totalOut, _lotSettlementFinished, "");

        // Calculate fees
        uint256 prefundedCuratorFees = _curatorApproved ? _curatorMaxPotentialFee : 0;
        uint256 curatorPayout = _calculateCuratorFee(totalOut);
        (,, uint256 totalQuoteTokenFees) = _calculateFees(_REFERRER, totalIn);

        // Set up expected values
        // Quote token
        _expectedAuctionHouseQuoteTokenBalance = _scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL); // To be claimed by bidders
        _expectedSellerQuoteTokenBalance = 0;

        // Base token
        _expectedAuctionHouseBaseTokenBalance = scaledLotCapacity + prefundedCuratorFees;
        _expectedSellerBaseTokenBalance = 0;

        _expectedCuratorBaseTokenRewards = 0;
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
    // [X] when settlement is not finished
    //  [X] no transfers or allocations are made
    // [X] when settlement is finished
    //  [X] it sets the lot as settled
    // [X] when the auction does not settle
    //  [X] when curated is true
    //   [X] it transfers the lot capacity and prepaid curator payout to the seller
    //  [X] it transfers the lot capacity to the seller
    // [X] when there is a partial fill
    //  [X] when curated is true
    //   [X] it transfers the proceeds to the seller, and allocates the curator payout
    //  [X] it transfers the proceeds to the seller
    // [X] when under capacity
    //  [X] when curated is true
    //   [X] it transfers the remaining lot capacity and curator payout to the seller, and allocates the curator payout
    //  [X] given the auction callback has the send base tokens flag
    //   [X] it refunds the base tokens to the callback
    //  [X] it transfers the remaining lot capacity to the seller
    // [X] when protocol fees are set
    //  [X] it transfers the proceeds - protocol fees to the seller
    // [X] when referrer fees are set
    //  [X] when protocol fees are set
    //   [X] it transfers the proceeds - protocol fees - referrer fees to the seller
    //  [X] it transfers the proceeds - referrer fees to the seller
    // [X] given the auction callback has the receive quote tokens flag
    //  [X] when the quote token transfer to the callback fails
    //   [X] it reverts
    //  [X] it sends the quote tokens to the callback
    // [X] given the auction callback has the onSettle flag
    //  [X] it calls the callback
    // [X] when curated is true
    //  [X] it transfers the remaining lot capacity and curator payout to the seller, and allocates the curator payout
    // [X] it transfers the remaining lot capacity to the seller
    // [X] when the callback reverts
    //  [X] it reverts
    // [X] when the quote token transfer to the seller fails
    //  [X] it reverts

    function test_whenLotIdIsInvalid_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);
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
        _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);
    }

    function test_whenSettlementDoesNotFinish()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
        givenLotIsConcluded
        givenLotSettlementNotFinished
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotDoesNotSettle
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
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
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        // Assertions are not updated with the curator fee, so the test will fail if the new curator fee is used by the AuctionHouse
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_partialFill_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_partialFill_callbackSendBaseTokens_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_partialFill_callbackSendBaseTokens_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_partialFill_callbackReceiveQuoteTokens_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_partialFill_callbackReceivesQuoteTokens_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_partialFill_callbackSendsAndReceives_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_partialFill_callbackSendsAndReceives_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_partialFill_callback_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasPartialFill
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
        givenOnSettleCallbackReverts
    {
        // Expect revert
        vm.expectRevert("revert");

        // Call function
        _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_underCapacity_callbackSendBaseTokens_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_underCapacity_callbackSendBaseTokens_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_underCapacity_callbackReceiveQuoteTokens_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_underCapacity_callbackReceivesQuoteTokens_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_underCapacity_callbackSendsAndReceives_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_underCapacity_callbackSendsAndReceives_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotIsUnderCapacity
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_capacityFilled_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_capacityFilled_quoteTokenTransferReverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
        givenRecipientIsOnQuoteTokenBlacklist(_SELLER)
    {
        // Expect revert
        // The raw "blacklist" revert is swallowed by safeTransfer
        vm.expectRevert("TRANSFER_FAILED");

        // Call function
        _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
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
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT_TOTAL))
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_capacityFilled_callbackSendBaseTokens_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_capacityFilled_callbackSendBaseTokens_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_capacityFilled_callbackReceiveQuoteTokens_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_capacityFilled_callbackReceivesQuoteTokens_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_capacityFilled_callbackReceivesQuoteTokens_quoteTokenTransferReverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
        givenRecipientIsOnQuoteTokenBlacklist(address(_callback))
    {
        // Expect revert
        // The raw "blacklist" revert is swallowed by safeTransfer
        vm.expectRevert("TRANSFER_FAILED");

        // Call function
        _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);
    }

    function test_capacityFilled_callbackSendsAndReceives_curated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }

    function test_capacityFilled_callbackSendsAndReceives_notCurated()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotCapacityIsFilled
        givenAuctionHouseHasQuoteTokenBalance(_BID_AMOUNT_TOTAL)
    {
        // Call function
        (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput) =
            _auctionHouse.settle(_lotId, _SETTLE_BATCH_SIZE, _ON_SETTLE_CALLBACK_PARAMS);

        // Check balances
        _assertBaseTokenBalances();
        _assertQuoteTokenBalances();
        _assertAccruedFees();
        _assertState();
        _assertLotSettlementOutput(totalIn, totalOut, finished, auctionOutput);
    }
}
