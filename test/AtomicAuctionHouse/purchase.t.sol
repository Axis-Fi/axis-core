// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuctionHouse} from "../../src/interfaces/IAuctionHouse.sol";
import {IAuction} from "../../src/interfaces/modules/IAuction.sol";
import {AtomicAuctionHouse} from "../../src/AtomicAuctionHouse.sol";

import {MockDerivativeModule} from "../modules/derivatives/mocks/MockDerivativeModule.sol";

import {AtomicAuctionHouseTest} from "./AuctionHouseTest.sol";

contract AtomicPurchaseTest is AtomicAuctionHouseTest {
    uint256 internal constant _AMOUNT_IN = 2e18;
    uint256 internal constant _PAYOUT_MULTIPLIER = 5000; // 50%

    address internal constant _SENDER = address(0x26);

    /// @dev Set by whenPayoutMultiplierIsSet
    uint256 internal _amountOut;
    /// @dev Set by whenPayoutMultiplierIsSet
    uint256 internal _curatorFeeActual;

    bytes internal _purchaseAuctionData = abi.encode("");

    uint48 internal constant _DERIVATIVE_EXPIRY = 1 days;
    uint256 internal _derivativeTokenId = type(uint256).max;

    uint256 internal _expectedSellerQuoteTokenBalance;
    uint256 internal _expectedBidderQuoteTokenBalance;
    uint256 internal _expectedAuctionHouseQuoteTokenBalance;
    uint256 internal _expectedCallbackQuoteTokenBalance;

    uint256 internal _expectedSellerBaseTokenBalance;
    uint256 internal _expectedBidderBaseTokenBalance;
    uint256 internal _expectedAuctionHouseBaseTokenBalance;
    uint256 internal _expectedCuratorBaseTokenBalance;
    uint256 internal _expectedDerivativeModuleBaseTokenBalance;

    uint256 internal _expectedBidderDerivativeTokenBalance;
    uint256 internal _expectedCuratorDerivativeTokenBalance;

    uint256 internal _expectedProtocolFeesAllocated;
    uint256 internal _expectedReferrerFeesAllocated;

    // ======== Modifiers ======== //

    modifier whenPurchaseReverts() {
        _atomicAuctionModule.setPurchaseReverts(true);
        _;
    }

    modifier whenPayoutMultiplierIsSet(
        uint256 multiplier_
    ) {
        _atomicAuctionModule.setPayoutMultiplier(_lotId, multiplier_);

        uint256 amountInLessFees = _scaleQuoteTokenAmount(_AMOUNT_IN)
            - _expectedProtocolFeesAllocated - _expectedReferrerFeesAllocated;
        amountInLessFees = amountInLessFees * _BASE_SCALE / (10 ** _quoteToken.decimals());

        // Set the amount out
        _amountOut = _scaleBaseTokenAmount((amountInLessFees * multiplier_) / 100e2);
        _curatorFeeActual = (_amountOut * _curatorFeePercentActual) / 100e2;
        _;
    }

    modifier givenDerivativeParamsAreSet() {
        MockDerivativeModule.DerivativeParams memory deployParams =
            MockDerivativeModule.DerivativeParams({expiry: _DERIVATIVE_EXPIRY, multiplier: 0});
        _derivativeParams = abi.encode(deployParams);
        _routingParams.derivativeParams = _derivativeParams;
        _;
    }

    modifier givenDerivativeIsDeployed() {
        // Deploy a new derivative token
        (uint256 tokenId,) = _derivativeModule.deploy(address(_baseToken), _derivativeParams, false);

        // Set up a new auction with a derivative
        _derivativeTokenId = tokenId;
        _;
    }

    modifier givenFeesAreCalculated(
        uint256 amountIn_
    ) {
        _expectedReferrerFeesAllocated = (amountIn_ * _referrerFeePercentActual) / 100e2;
        _expectedProtocolFeesAllocated = (amountIn_ * _protocolFeePercentActual) / 100e2;
        _;
    }

    modifier givenFeesAreCalculatedNoReferrer(
        uint256 amountIn_
    ) {
        _expectedReferrerFeesAllocated = 0;
        _expectedProtocolFeesAllocated =
            (amountIn_ * (_protocolFeePercentActual + _referrerFeePercentActual)) / 100e2;
        _;
    }

    modifier givenBalancesAreCalculated(uint256 amountIn_, uint256 amountOut_) {
        // Determine curator fee
        uint256 curatorFee = _curatorApproved ? (amountOut_ * _curatorFeePercentActual) / 100e2 : 0;
        bool hasDerivativeToken = _derivativeTokenId != type(uint256).max;
        bool hasCallback = address(_routingParams.callbacks) != address(0);
        uint256 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);
        uint256 scaledCuratorMaxPotentialFee = _curatorMaxPotentialFee;

        uint256 amountInLessFees =
            amountIn_ - _expectedProtocolFeesAllocated - _expectedReferrerFeesAllocated;

        // Quote token
        _expectedSellerQuoteTokenBalance =
            hasCallback && _callbackReceiveQuoteTokens ? 0 : amountInLessFees;
        _expectedBidderQuoteTokenBalance = 0;
        _expectedAuctionHouseQuoteTokenBalance =
            _expectedProtocolFeesAllocated + _expectedReferrerFeesAllocated;
        _expectedCallbackQuoteTokenBalance =
            hasCallback && _callbackReceiveQuoteTokens ? amountInLessFees : 0;
        assertEq(
            _expectedSellerQuoteTokenBalance + _expectedBidderQuoteTokenBalance
                + _expectedAuctionHouseQuoteTokenBalance + _expectedCallbackQuoteTokenBalance,
            amountIn_,
            "quote token: total balance mismatch"
        );

        // Base token
        _expectedSellerBaseTokenBalance = 0;
        _expectedBidderBaseTokenBalance = hasDerivativeToken ? 0 : _amountOut;
        _expectedAuctionHouseBaseTokenBalance = 0;
        _expectedCuratorBaseTokenBalance = hasDerivativeToken ? 0 : curatorFee;
        _expectedDerivativeModuleBaseTokenBalance = hasDerivativeToken ? _amountOut + curatorFee : 0;
        assertEq(
            _expectedSellerBaseTokenBalance + _expectedBidderBaseTokenBalance
                + _expectedAuctionHouseBaseTokenBalance + _expectedCuratorBaseTokenBalance
                + _expectedDerivativeModuleBaseTokenBalance,
            amountOut_ + curatorFee,
            "base token: total balance mismatch"
        );

        // Derivative token
        _expectedBidderDerivativeTokenBalance = hasDerivativeToken ? _amountOut : 0;
        _expectedCuratorDerivativeTokenBalance = hasDerivativeToken ? curatorFee : 0;
        _;
    }

    // ======== Helper Functions ======== //

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
        assertEq(_baseToken.balanceOf(address(_callback)), 0, "base token: callback balance");
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
        assertEq(
            _quoteToken.balanceOf(address(_callback)),
            _expectedCallbackQuoteTokenBalance,
            "quote token: callback balance"
        );
    }

    function _assertDerivativeTokenBalances() internal {
        // Check derivative token balances
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_bidder, _derivativeTokenId),
            _expectedBidderDerivativeTokenBalance,
            "derivative token: bidder balance"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_CURATOR, _derivativeTokenId),
            _expectedCuratorDerivativeTokenBalance,
            "derivative token: curator balance"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(address(_callback), _derivativeTokenId),
            0,
            "derivative token: callback balance"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(
                address(_auctionHouse), _derivativeTokenId
            ),
            0,
            "derivative token: auction house balance"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_SELLER, _derivativeTokenId),
            0,
            "derivative token: seller balance"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_PROTOCOL, _derivativeTokenId),
            0,
            "derivative token: protocol balance"
        );
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

    function _assertPrefunding() internal {
        // Check funding amount
        IAuctionHouse.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, 0, "mismatch on funding");
    }

    // ======== Tests ======== //

    // parameter checks
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the auction is not active
    //  [X] it reverts
    // [X] when the auction module reverts
    //  [X] it reverts

    function test_whenLotIdIsInvalid_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);
    }

    function test_whenAuctionNotActive_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotIsCancelled
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenSellerHasBaseTokenBalance(_amountOut)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);
    }

    function test_whenAuctionModuleReverts_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenSellerHasBaseTokenBalance(_amountOut)
        whenPurchaseReverts
    {
        // Expect revert
        vm.expectRevert("error");

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);
    }

    function test_whenPayoutAmountLessThanMinimum_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(9000)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AtomicAuctionHouse.AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Purchase
        _createPurchase(_AMOUNT_IN, _AMOUNT_IN, _purchaseAuctionData);
    }

    // allowlist
    // [X] given an allowlist is set
    //  [X] when the caller is not on the allowlist
    //   [X] it reverts
    //  [X] when the caller is on the allowlist
    //   [X] it succeeds

    function test_givenCallerNotOnAllowlist_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotHasAllowlist
        whenAllowlistProofIsIncorrect
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Expect revert
        bytes memory err = abi.encodePacked("not allowed");
        vm.expectRevert(err);

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);
    }

    function test_givenCallerOnAllowlist()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotHasAllowlist
        whenAllowlistProofIsCorrect
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    // transfer quote token to auction house
    // [X] when the permit2 signature is provided
    //  [X] it succeeds using Permit2
    // [X] when the permit2 signature is not provided
    //  [X] it succeeds using ERC20 transfer

    function test_whenPermit2Signature()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        whenPermit2ApprovalIsProvided(_AMOUNT_IN)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_whenPermit2Signature_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        whenPermit2ApprovalIsProvided(_scaleQuoteTokenAmount(_AMOUNT_IN))
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_whenPermit2Signature_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        whenPermit2ApprovalIsProvided(_scaleQuoteTokenAmount(_AMOUNT_IN))
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_whenNoPermit2Signature()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_whenNoPermit2Signature_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_whenNoPermit2Signature_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    // [X] given the auction has callbacks defined
    //  [X] given the callback has the receive quote tokens flag
    //   [X] it succeeds - payout token transferred from seller, quote token transferred to callback, quote token (minus fees) transferred to _bidder
    //  [X] given the callback has the send base tokens flag
    //   [X] it succeeds - payout token transferred from callback, quote token transferred to seller, payout token (minus fees) transferred to _bidder
    //  [X] it succeeds - quote token transferred to seller, payout token (minus fees) transferred to _bidder
    // [X] given the auction does not have callbacks defined
    //  [X] it succeeds - quote token transferred to seller, payout token (minus fees) transferred to _bidder

    function test_callbacks_givenCallbackSendBaseTokensFlag()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenCallbackHasBaseTokenBalance(_amountOut)
        givenCallbackHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();

        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
    }

    function test_callbacks_givenCallbackSendBaseTokensFlag_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenCallbackHasBaseTokenBalance(_amountOut)
        givenCallbackHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();

        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
    }

    function test_callbacks_givenCallbackSendBaseTokensFlag_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenCallbackHasBaseTokenBalance(_amountOut)
        givenCallbackHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();

        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
    }

    function test_callbacks_givenCallbackReceiveQuoteTokensFlag()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackHasReceiveQuoteTokensFlag
        givenCallbackIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();

        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
    }

    function test_callbacks()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();

        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
    }

    function test_noCallbacks()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_noCallbacks_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_noCallbacks_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    // ======== Derivative flow ======== //

    // [X] given the auction has a derivative defined
    //  [X] it succeeds - derivative is minted

    function test_derivative()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        givenDerivativeParamsAreSet
        givenDerivativeIsDeployed
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Call
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_derivative_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        givenDerivativeParamsAreSet
        givenDerivativeIsDeployed
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Call
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_derivative_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        givenDerivativeParamsAreSet
        givenDerivativeIsDeployed
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Call
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    // [X] given there is no _PROTOCOL fee set for the auction type
    //  [X] no _PROTOCOL fee is accrued
    // [X] the _PROTOCOL fee is accrued

    function test_givenProtocolFeeIsNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenProtocolFeeIsNotSet_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenProtocolFeeIsNotSet_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenProtocolFeeIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenProtocolFeeIsSet_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenProtocolFeeIsSet_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    // [X] given there is no _REFERRER fee set for the auction type
    //  [X] no _REFERRER fee is accrued
    // [X] the _REFERRER fee is accrued

    function test_givenReferrerFeeIsNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenReferrerFeeIsNotSet_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenReferrerFeeIsNotSet_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenReferrerFeeIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenReferrerFeeIsSet_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenReferrerFeeIsSet_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenReferrerIsNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculatedNoReferrer(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(
            _scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData, address(0)
        );

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    // [X] given there is no curator set
    //  [X] no payout token is transferred to the curator
    // [X] given there is a curator set
    //  [X] given the curator has not approved curation
    //   [X] no payout token is transferred to the curator
    //  [X] given the payout token is a derivative
    //   [X] derivative is minted and transferred to the curator
    //  [X] payout token is transferred to the curator
    //  [X] given the curator fee has been changed
    //   [X] it uses the original curator fee

    function test_givenCuratorIsNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenCuratorIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenCuratorHasApproved()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenSellerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenCuratorHasApproved_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenSellerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenCuratorHasApproved_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenSellerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenCuratorHasApproved_givenCuratorFeeNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenCuratorMaxFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut)
        givenSellerHasBaseTokenAllowance(_amountOut)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_givenCuratorHasApproved_givenCuratorFeeIsChanged()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenSellerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
    {
        // Change the curator fee
        _setCuratorFee(95);

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        // Assertions are not updated with the curator fee, so the test will fail if the new curator fee is used by the AuctionHouse
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_derivative_givenCuratorHasApproved()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        givenDerivativeParamsAreSet
        givenDerivativeIsDeployed
        givenCuratorIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenFeesAreCalculated(_AMOUNT_IN)
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenSellerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_derivative_givenCuratorHasApproved_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        givenDerivativeParamsAreSet
        givenDerivativeIsDeployed
        givenCuratorIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenSellerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    function test_derivative_givenCuratorHasApproved_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        givenDerivativeParamsAreSet
        givenDerivativeIsDeployed
        givenCuratorIsSet
        givenProtocolFeeIsSet
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_AMOUNT_IN))
        givenFeesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN))
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenSellerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenSellerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenBalancesAreCalculated(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut)
    {
        // Purchase
        _createPurchase(_scaleQuoteTokenAmount(_AMOUNT_IN), _amountOut, _purchaseAuctionData);

        // Check state
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
        _assertDerivativeTokenBalances();
        _assertAccruedFees();
        _assertPrefunding();
    }

    // [X] when the recipient is not the sender
    //  [X] when the recipient is the zero address
    //   [X] it treats sender as the recipient
    //   [X] when a callback is set
    //    [X] when the callback has the send base tokens flag
    //     [X] it sends the sender to the onPurchase callback
    //    [X] it sends the sender to the onPurchase callback
    //  [X] when the recipient is not the zero address
    //   [X] it treats the recipient param as the recipient
    //   [X] when a callback is set
    //    [X] when the callback has the send base tokens flag
    //     [X] it sends the recipient to the onPurchase callback
    //    [X] it sends the recipient to the onPurchase callback

    function test_whenSenderIsNotRecipient_whenRecipientIsZeroAddress()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Fund the sender
        _sendUserQuoteTokenBalance(_SENDER, _AMOUNT_IN);
        _approveUserQuoteTokenAllowance(_SENDER, _AMOUNT_IN);

        // Cache sender balance
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);

        // Call the function
        _createPurchase(
            _SENDER, address(0), _AMOUNT_IN, _amountOut, _purchaseAuctionData, _REFERRER
        );

        // Quote token balances
        assertEq(_quoteToken.balanceOf(_SENDER), senderBalance - _AMOUNT_IN, "quote token: sender");

        // Base token balances
        assertEq(
            _baseToken.balanceOf(_SENDER), _expectedBidderBaseTokenBalance, "base token: sender"
        );
        assertEq(_baseToken.balanceOf(_RECIPIENT), 0, "base token: recipient");
    }

    function test_whenSenderIsNotRecipient_whenRecipientIsZeroAddress_givenCallbackIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Fund the sender
        _sendUserQuoteTokenBalance(_SENDER, _AMOUNT_IN);
        _approveUserQuoteTokenAllowance(_SENDER, _AMOUNT_IN);

        // Cache sender balance
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);

        // Call the function
        _createPurchase(
            _SENDER, address(0), _AMOUNT_IN, _amountOut, _purchaseAuctionData, _REFERRER
        );

        // Quote token balances
        assertEq(_quoteToken.balanceOf(_SENDER), senderBalance - _AMOUNT_IN, "quote token: sender");

        // Base token balances
        assertEq(
            _baseToken.balanceOf(_SENDER), _expectedBidderBaseTokenBalance, "base token: sender"
        );
        assertEq(_baseToken.balanceOf(_RECIPIENT), 0, "base token: recipient");

        // Check that the callback was called, and the sender was passed as the buyer
        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
        assertEq(_callback.buyers(_lotId, 0), _SENDER, "buyers[0]");
    }

    function test_whenSenderIsNotRecipient_whenRecipientIsZeroAddress_givenCallbackIsSet_givenCallbackSendBaseTokensFlag(
    )
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Fund the sender
        _sendUserQuoteTokenBalance(_SENDER, _AMOUNT_IN);
        _approveUserQuoteTokenAllowance(_SENDER, _AMOUNT_IN);

        // Cache sender balance
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);

        // Call the function
        _createPurchase(
            _SENDER, address(0), _AMOUNT_IN, _amountOut, _purchaseAuctionData, _REFERRER
        );

        // Quote token balances
        assertEq(_quoteToken.balanceOf(_SENDER), senderBalance - _AMOUNT_IN, "quote token: sender");

        // Base token balances
        assertEq(
            _baseToken.balanceOf(_SENDER), _expectedBidderBaseTokenBalance, "base token: sender"
        );
        assertEq(_baseToken.balanceOf(_RECIPIENT), 0, "base token: recipient");

        // Check that the callback was called, and the sender was passed as the buyer
        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
        assertEq(_callback.buyers(_lotId, 0), _SENDER, "buyers[0]");
    }

    function test_whenSenderIsNotRecipient()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Fund the sender
        _sendUserQuoteTokenBalance(_SENDER, _AMOUNT_IN);
        _approveUserQuoteTokenAllowance(_SENDER, _AMOUNT_IN);

        // Cache sender balance
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);

        // Call the function
        _createPurchase(
            _SENDER, _RECIPIENT, _AMOUNT_IN, _amountOut, _purchaseAuctionData, _REFERRER
        );

        // Quote token balances
        assertEq(_quoteToken.balanceOf(_SENDER), senderBalance - _AMOUNT_IN, "quote token: sender");

        // Base token balances
        assertEq(_baseToken.balanceOf(_SENDER), 0, "base token: sender");
        assertEq(
            _baseToken.balanceOf(_RECIPIENT),
            _expectedBidderBaseTokenBalance,
            "base token: recipient"
        );
    }

    function test_whenSenderIsNotRecipient_givenCallbackIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Fund the sender
        _sendUserQuoteTokenBalance(_SENDER, _AMOUNT_IN);
        _approveUserQuoteTokenAllowance(_SENDER, _AMOUNT_IN);

        // Cache sender balance
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);

        // Call the function
        _createPurchase(
            _SENDER, _RECIPIENT, _AMOUNT_IN, _amountOut, _purchaseAuctionData, _REFERRER
        );

        // Quote token balances
        assertEq(_quoteToken.balanceOf(_SENDER), senderBalance - _AMOUNT_IN, "quote token: sender");

        // Base token balances
        assertEq(_baseToken.balanceOf(_SENDER), 0, "base token: sender");
        assertEq(
            _baseToken.balanceOf(_RECIPIENT),
            _expectedBidderBaseTokenBalance,
            "base token: recipient"
        );

        // Check that the callback was called, and the recipient was passed as the buyer
        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
        assertEq(_callback.buyers(_lotId, 0), _RECIPIENT, "buyers[0]");
    }

    function test_whenSenderIsNotRecipient_givenCallbackIsSet_givenCallbackSendBaseTokensFlag()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
        whenPayoutMultiplierIsSet(_PAYOUT_MULTIPLIER)
        givenBalancesAreCalculated(_AMOUNT_IN, _amountOut)
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Fund the sender
        _sendUserQuoteTokenBalance(_SENDER, _AMOUNT_IN);
        _approveUserQuoteTokenAllowance(_SENDER, _AMOUNT_IN);

        // Cache sender balance
        uint256 senderBalance = _quoteToken.balanceOf(_SENDER);

        // Call the function
        _createPurchase(
            _SENDER, _RECIPIENT, _AMOUNT_IN, _amountOut, _purchaseAuctionData, _REFERRER
        );

        // Quote token balances
        assertEq(_quoteToken.balanceOf(_SENDER), senderBalance - _AMOUNT_IN, "quote token: sender");

        // Base token balances
        assertEq(_baseToken.balanceOf(_SENDER), 0, "base token: sender");
        assertEq(
            _baseToken.balanceOf(_RECIPIENT),
            _expectedBidderBaseTokenBalance,
            "base token: recipient"
        );

        // Check that the callback was called, and the recipient was passed as the buyer
        assertEq(_callback.lotPurchased(_lotId), true, "lotPurchased");
        assertEq(_callback.buyers(_lotId, 0), _RECIPIENT, "buyers[0]");
    }
}
