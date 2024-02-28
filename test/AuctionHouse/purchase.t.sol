// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auctioneer} from "src/bases/Auctioneer.sol";
import {Auction} from "src/modules/Auction.sol";
import {AuctionHouse} from "src/AuctionHouse.sol";
import {FeeManager} from "src/bases/FeeManager.sol";

import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract PurchaseTest is AuctionHouseTest {
    uint96 internal constant _AMOUNT_IN = 1e18;
    uint96 internal _amountInReferrerFee = (_AMOUNT_IN * _REFERRER_FEE_PERCENT) / 1e5;
    uint96 internal _amountInProtocolFee = (_AMOUNT_IN * _PROTOCOL_FEE_PERCENT) / 1e5;
    uint96 internal _amountInLessFee = _AMOUNT_IN - _amountInReferrerFee - _amountInProtocolFee;
    // 1:1 exchange rate
    uint96 internal _amountOut = _amountInLessFee;

    bytes internal _purchaseAuctionData = abi.encode("");

    uint96 internal _curatorFeeActual = _amountOut * _CURATOR_FEE_PERCENT / 1e5;

    uint48 internal constant _DERIVATIVE_EXPIRY = 1 days;
    uint256 internal _derivativeTokenId = type(uint256).max;

    modifier whenPurchaseReverts() {
        _atomicAuctionModule.setPurchaseReverts(true);
        _;
    }

    modifier whenPayoutMultiplierIsSet(uint256 multiplier_) {
        _atomicAuctionModule.setPayoutMultiplier(_lotId, multiplier_);
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

    // parameter checks
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given the auction is not atomic
    //  [X] it reverts
    // [X] given the auction is not active
    //  [X] it reverts
    // [X] when the auction module reverts
    //  [X] it reverts

    function test_whenLotIdIsInvalid_reverts() external {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);
    }

    function test_whenNotAtomicAuction_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
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
        givenOwnerHasBaseTokenBalance(_amountOut)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
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
        givenOwnerHasBaseTokenBalance(_amountOut)
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
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        whenPayoutMultiplierIsSet(90_000)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.AmountLessThanMinimum.selector);
        vm.expectRevert(err);

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);
    }

    // allowlist
    // [X] given an allowlist is set
    //  [X] when the caller is not on the allowlist
    //   [X] it reverts
    //  [X] when the caller is on the allowlist
    //   [X] it succeeds

    function test_givenCallerNotOnAllowlist()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotHasAllowlist
        whenAllowlistProofIsIncorrect
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidBidder.selector, _bidder);
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
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Caller has no quote tokens
        assertEq(_quoteToken.balanceOf(_bidder), 0);

        // Recipient has base tokens
        assertEq(_baseToken.balanceOf(_bidder), _amountInLessFee);
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
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
        whenPermit2ApprovalIsProvided(_AMOUNT_IN)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0);
        assertEq(_quoteToken.balanceOf(address(_hook)), 0);
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInProtocolFee + _amountInReferrerFee
        );
        assertEq(_quoteToken.balanceOf(_auctionOwner), _amountInLessFee);

        // Ignore the rest
    }

    function test_whenNoPermit2Signature()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0);
        assertEq(_quoteToken.balanceOf(address(_hook)), 0);
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInProtocolFee + _amountInReferrerFee
        );
        assertEq(_quoteToken.balanceOf(_auctionOwner), _amountInLessFee);

        // Ignore the rest
    }

    // [X] given the auction has hooks defined
    //  [X] it succeeds - quote token transferred to hook, payout token (minus fees) transferred to _bidder
    // [X] given the auction does not have hooks defined
    //  [X] it succeeds - quote token transferred to auction owner, payout token (minus fees) transferred to _bidder

    function test_hooks()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAuctionHasHook
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenHookHasBaseTokenBalance(_amountOut)
        givenHookHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0);
        assertEq(_quoteToken.balanceOf(address(_hook)), _amountInLessFee);
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInProtocolFee + _amountInReferrerFee
        );
        assertEq(_quoteToken.balanceOf(_auctionOwner), 0);

        assertEq(_baseToken.balanceOf(_bidder), _amountOut);
        assertEq(_baseToken.balanceOf(address(_hook)), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_auctionOwner), 0);

        // Check accrued fees
        assertEq(_auctionHouse.rewards(_bidder, _quoteToken), 0);
        assertEq(_auctionHouse.rewards(_REFERRER, _quoteToken), _amountInReferrerFee);
        assertEq(_auctionHouse.rewards(_PROTOCOL, _quoteToken), _amountInProtocolFee);
        assertEq(_auctionHouse.rewards(address(_hook), _quoteToken), 0);
        assertEq(_auctionHouse.rewards(address(_auctionHouse), _quoteToken), 0);
        assertEq(_auctionHouse.rewards(_auctionOwner, _quoteToken), 0);

        assertEq(_auctionHouse.rewards(_bidder, _baseToken), 0);
        assertEq(_auctionHouse.rewards(_REFERRER, _baseToken), 0);
        assertEq(_auctionHouse.rewards(_PROTOCOL, _baseToken), 0);
        assertEq(_auctionHouse.rewards(address(_hook), _baseToken), 0);
        assertEq(_auctionHouse.rewards(address(_auctionHouse), _baseToken), 0);
        assertEq(_auctionHouse.rewards(_auctionOwner, _baseToken), 0);

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, 0, "mismatch on prefunding");
    }

    function test_noHooks()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0);
        assertEq(_quoteToken.balanceOf(address(_hook)), 0);
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInProtocolFee + _amountInReferrerFee
        );
        assertEq(_quoteToken.balanceOf(_auctionOwner), _amountInLessFee);

        assertEq(_baseToken.balanceOf(_bidder), _amountOut);
        assertEq(_baseToken.balanceOf(address(_hook)), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_auctionOwner), 0);

        // Check accrued fees
        assertEq(_auctionHouse.rewards(_bidder, _quoteToken), 0);
        assertEq(_auctionHouse.rewards(_REFERRER, _quoteToken), _amountInReferrerFee);
        assertEq(_auctionHouse.rewards(_PROTOCOL, _quoteToken), _amountInProtocolFee);
        assertEq(_auctionHouse.rewards(address(_hook), _quoteToken), 0);
        assertEq(_auctionHouse.rewards(address(_auctionHouse), _quoteToken), 0);
        assertEq(_auctionHouse.rewards(_auctionOwner, _quoteToken), 0);

        assertEq(_auctionHouse.rewards(_bidder, _baseToken), 0);
        assertEq(_auctionHouse.rewards(_REFERRER, _baseToken), 0);
        assertEq(_auctionHouse.rewards(_PROTOCOL, _baseToken), 0);
        assertEq(_auctionHouse.rewards(address(_hook), _baseToken), 0);
        assertEq(_auctionHouse.rewards(address(_auctionHouse), _baseToken), 0);
        assertEq(_auctionHouse.rewards(_auctionOwner, _baseToken), 0);

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, 0, "mismatch on prefunding");
    }

    // ======== Derivative flow ======== //

    // [X] given the auction has a derivative defined
    //  [X] it succeeds - derivative is minted

    function test_derivative()
        public
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        givenDerivativeParamsAreSet
        givenDerivativeIsDeployed
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Call
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances of the quote token
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInProtocolFee + _amountInReferrerFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(
            _quoteToken.balanceOf(address(_derivativeModule)),
            0,
            "quote token: balance mismatch on derivative module"
        );

        // Check balances of the base token
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: balance mismatch on _bidder");
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_derivativeModule)),
            _amountOut,
            "base token: balance mismatch on derivative module"
        );

        // Check balances of the derivative token
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_bidder, _derivativeTokenId),
            _amountOut,
            "derivative token: balance mismatch on _bidder"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(address(_hook), _derivativeTokenId),
            0,
            "derivative token: balance mismatch on hook"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(
                address(_auctionHouse), _derivativeTokenId
            ),
            0,
            "derivative token: balance mismatch on auction house"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_auctionOwner, _derivativeTokenId),
            0,
            "derivative token: balance mismatch on auction owner"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(
                address(_derivativeModule), _derivativeTokenId
            ),
            0,
            "derivative token: balance mismatch on derivative module"
        );
    }

    // [X] given there is no _PROTOCOL fee set for the auction type
    //  [X] no _PROTOCOL fee is accrued
    // [X] the _PROTOCOL fee is accrued

    modifier givenProtocolFeeIsNotSet() {
        _auctionHouse.setFee(_auctionModuleKeycode, FeeManager.FeeType.Protocol, 0);

        _amountInProtocolFee = 0;
        _amountInLessFee = _AMOUNT_IN - _amountInReferrerFee;
        _amountOut = _amountInLessFee;
        _;
    }

    function test_givenProtocolFeeIsNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsNotSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInReferrerFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: balance mismatch on curator");

        assertEq(
            _baseToken.balanceOf(_bidder), _amountOut, "base token: balance mismatch on _bidder"
        );
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_CURATOR)), 0, "base token: balance mismatch on curator"
        );

        // Check rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            0,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            _amountInReferrerFee,
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

    function test_givenProtocolFeeIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInReferrerFee + _amountInProtocolFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(
            _quoteToken.balanceOf(address(_CURATOR)), 0, "quote token: balance mismatch on curator"
        );

        assertEq(
            _baseToken.balanceOf(_bidder), _amountOut, "base token: balance mismatch on _bidder"
        );
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_CURATOR)), 0, "base token: balance mismatch on curator"
        );

        // Check rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            _amountInProtocolFee,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            _amountInReferrerFee,
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
    //  [X] no _REFERRER fee is accrued
    // [X] the _REFERRER fee is accrued

    modifier givenReferrerFeeIsNotSet() {
        _auctionHouse.setFee(_auctionModuleKeycode, FeeManager.FeeType.Referrer, 0);

        _amountInReferrerFee = 0;
        _amountInLessFee = _AMOUNT_IN - _amountInProtocolFee;
        _amountOut = _amountInLessFee;
        _;
    }

    function test_givenReferrerFeeIsNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenReferrerFeeIsNotSet
        givenProtocolFeeIsSet
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInProtocolFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(
            _quoteToken.balanceOf(address(_CURATOR)), 0, "quote token: balance mismatch on curator"
        );

        assertEq(
            _baseToken.balanceOf(_bidder), _amountOut, "base token: balance mismatch on _bidder"
        );
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_CURATOR)), 0, "base token: balance mismatch on curator"
        );

        // Check rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            _amountInProtocolFee,
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

    function test_givenReferrerFeeIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInReferrerFee + _amountInProtocolFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(
            _quoteToken.balanceOf(address(_CURATOR)), 0, "quote token: balance mismatch on curator"
        );

        assertEq(
            _baseToken.balanceOf(_bidder), _amountOut, "base token: balance mismatch on _bidder"
        );
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_CURATOR)), 0, "base token: balance mismatch on curator"
        );

        // Check rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            _amountInProtocolFee,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            _amountInReferrerFee,
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
    //  [X] given the payout token is a derivative
    //   [X] derivative is minted and transferred to the curator
    //  [X] payout token is transferred to the curator

    function test_givenCuratorIsNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInReferrerFee + _amountInProtocolFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(
            _quoteToken.balanceOf(address(_CURATOR)), 0, "quote token: balance mismatch on curator"
        );

        assertEq(
            _baseToken.balanceOf(_bidder), _amountOut, "base token: balance mismatch on _bidder"
        );
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_CURATOR)), 0, "base token: balance mismatch on curator"
        );

        // Check rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            _amountInProtocolFee,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            _amountInReferrerFee,
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

    function test_givenCuratorIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
        givenOwnerHasBaseTokenBalance(_amountOut)
        givenOwnerHasBaseTokenAllowance(_amountOut)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInReferrerFee + _amountInProtocolFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(
            _quoteToken.balanceOf(address(_CURATOR)), 0, "quote token: balance mismatch on curator"
        );

        assertEq(
            _baseToken.balanceOf(_bidder), _amountOut, "base token: balance mismatch on _bidder"
        );
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_CURATOR)), 0, "base token: balance mismatch on curator"
        );

        // Check rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            _amountInProtocolFee,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            _amountInReferrerFee,
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

    function test_givenCuratorHasApproved()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenOwnerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenOwnerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInReferrerFee + _amountInProtocolFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(
            _quoteToken.balanceOf(address(_CURATOR)), 0, "quote token: balance mismatch on curator"
        );

        assertEq(
            _baseToken.balanceOf(_bidder), _amountOut, "base token: balance mismatch on _bidder"
        );
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_CURATOR)),
            _curatorFeeActual,
            "base token: balance mismatch on curator"
        );

        // Check rewards
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken),
            _amountInProtocolFee,
            "quote token: _PROTOCOL rewards mismatch"
        );
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken),
            _amountInReferrerFee,
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

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, 0, "mismatch on prefunding");
    }

    function test_derivative_givenCuratorHasApproved()
        external
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        givenDerivativeParamsAreSet
        givenDerivativeIsDeployed
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenOwnerHasBaseTokenBalance(_amountOut + _curatorFeeActual)
        givenOwnerHasBaseTokenAllowance(_amountOut + _curatorFeeActual)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
    {
        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances of quote token
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: balance mismatch on _bidder");
        assertEq(_quoteToken.balanceOf(address(_hook)), 0, "quote token: balance mismatch on hook");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _amountInReferrerFee + _amountInProtocolFee,
            "quote token: balance mismatch on auction house"
        );
        assertEq(
            _quoteToken.balanceOf(_auctionOwner),
            _amountInLessFee,
            "quote token: balance mismatch on auction owner"
        );
        assertEq(
            _quoteToken.balanceOf(address(_CURATOR)), 0, "quote token: balance mismatch on curator"
        );
        assertEq(_quoteToken.balanceOf(address(_derivativeModule)), 0);

        // Check balances of base token
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: balance mismatch on _bidder");
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "base token: balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch on auction house"
        );
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: balance mismatch on auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_CURATOR)), 0, "base token: balance mismatch on curator"
        );
        assertEq(
            _baseToken.balanceOf(address(_derivativeModule)),
            _amountOut + _curatorFeeActual,
            "base token: balance mismatch on derivative module"
        );

        // Check balances of derivative token
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_bidder, _derivativeTokenId),
            _amountOut,
            "derivative token: balance mismatch on _bidder"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(address(_hook), _derivativeTokenId),
            0,
            "derivative token: balance mismatch on hook"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(
                address(_auctionHouse), _derivativeTokenId
            ),
            0,
            "derivative token: balance mismatch on auction house"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_auctionOwner, _derivativeTokenId),
            0,
            "derivative token: balance mismatch on auction owner"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(_CURATOR, _derivativeTokenId),
            _curatorFeeActual,
            "derivative token: balance mismatch on curator"
        );
        assertEq(
            _derivativeModule.derivativeToken().balanceOf(
                address(_derivativeModule), _derivativeTokenId
            ),
            0,
            "derivative token: balance mismatch on derivative module"
        );
    }

    // ======== Prefunding flow ======== //

    // [X] given the auction is prefunded
    //  [X] given the curator has approved
    //   [X] it succeeds - base token is not transferred from auction owner again
    //  [X] it succeeds - base token is not transferred from auction owner again

    modifier whenLotIsPrefunded() {
        _atomicAuctionModule.setRequiredPrefunding(true);
        _;
    }

    function test_prefunded()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenLotIsPrefunded
        givenCuratorIsSet
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
    {
        // Auction house has base tokens
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY,
            "pre-purchase: balance mismatch on auction house"
        );

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances of the base token
        assertEq(_baseToken.balanceOf(_bidder), _amountOut, "balance mismatch on _bidder");
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY - _amountOut,
            "balance mismatch on auction house"
        );
        assertEq(_baseToken.balanceOf(_auctionOwner), 0, "balance mismatch on auction owner");

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, _LOT_CAPACITY - _amountOut, "mismatch on prefunding");
    }

    function test_prefunded_givenCuratorHasApproved()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenLotIsPrefunded
        givenCuratorIsSet
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenReferrerFeeIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenOwnerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenOwnerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_AMOUNT_IN)
        givenUserHasQuoteTokenAllowance(_AMOUNT_IN)
    {
        // Auction house has base tokens
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "pre-purchase: balance mismatch on auction house"
        );

        // Purchase
        _createPurchase(_AMOUNT_IN, _amountOut, _purchaseAuctionData);

        // Check balances of the base token
        assertEq(_baseToken.balanceOf(_bidder), _amountOut, "balance mismatch on _bidder");
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "balance mismatch on hook");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee - _amountOut - _curatorFeeActual,
            "balance mismatch on auction house"
        );
        assertEq(_baseToken.balanceOf(_auctionOwner), 0, "balance mismatch on auction owner");
        assertEq(_baseToken.balanceOf(_CURATOR), _curatorFeeActual, "balance mismatch on curator");

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(
            lotPrefunding,
            _LOT_CAPACITY + _curatorMaxPotentialFee - _amountOut - _curatorFeeActual,
            "mismatch on prefunding"
        );
    }
}
