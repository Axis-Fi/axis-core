// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

import {Auctioneer} from "src/bases/Auctioneer.sol";
import {Auction} from "src/modules/Auction.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {Veecode, WithModules, wrapVeecode, fromVeecode} from "src/modules/Modules.sol";

contract AuctionTest is AuctionHouseTest {
    // Imported events
    event AuctionCreated(uint96 indexed _lotId, Veecode indexed auctionRef, string infoHash);

    // auction
    // [X] reverts when auction module is sunset
    // [X] reverts when auction module is not installed
    // [X] reverts when auction type is not auction
    // [X] reverts when base token decimals are out of bounds
    // [X] reverts when quote token decimals are out of bounds
    // [X] reverts when base token is 0
    // [X] reverts when quote token is 0
    // [X] reverts when the auction type is batch and prefunded is false
    // [X] creates the auction lot

    function test_whenModuleNotInstalled_reverts() external whenAuctionTypeIsAtomic {
        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleNotInstalled.selector, _atomicAuctionModuleKeycode, 0
        );
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenModuleTypeIncorrect_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        // Set the auction type to a derivative module
        _routingParams.auctionType = _derivativeModuleKeycode;

        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenModuleIsSunset_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        _auctionHouse.sunsetModule(_atomicAuctionModuleKeycode);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, _atomicAuctionModuleKeycode);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenBaseTokenDecimalsAreOutOfBounds_reverts(uint8 decimals_)
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        // Create a token with the decimals
        MockERC20 token = new MockERC20("Token", "TOK", decimals);

        // Update routing params
        _routingParams.baseToken = token;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenQuoteTokenDecimalsAreOutOfBounds_reverts(uint8 decimals_)
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        // Create a token with the decimals
        MockERC20 token = new MockERC20("Token", "TOK", decimals);

        // Update routing params
        _routingParams.quoteToken = token;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenBaseTokenIsZero_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        _routingParams.baseToken = ERC20(address(0));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenQuoteTokenIsZero_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        _routingParams.quoteToken = ERC20(address(0));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenAuctionTypeIsBatch_whenNotPrefunded_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
    {
        // Override the prefunded value
        _routingParams.prefunded = false;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_success() external whenAuctionTypeIsAtomic whenAtomicAuctionModuleIsInstalled {
        // Expect event to be emitted
        vm.expectEmit(address(_auctionHouse));
        emit AuctionCreated(0, wrapVeecode(_routingParams.auctionType, 1), _INFO_HASH);

        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(
            fromVeecode(routing.auctionReference),
            fromVeecode(wrapVeecode(_routingParams.auctionType, 1)),
            "auction type mismatch"
        );
        assertEq(routing.seller, _SELLER, "seller mismatch");
        assertEq(address(routing.baseToken), address(_baseToken), "base token mismatch");
        assertEq(address(routing.quoteToken), address(_quoteToken), "quote token mismatch");
        assertEq(address(routing.callbacks), address(0), "callback mismatch");
        assertEq(fromVeecode(routing.derivativeReference), "", "derivative type mismatch");
        assertEq(routing.derivativeParams, "", "derivative params mismatch");
        assertEq(routing.wrapDerivative, false, "wrap derivative mismatch");
        assertEq(routing.funding, 0, "funding mismatch");

        // Curation updated
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator mismatch");
        assertEq(curation.curated, false, "curated mismatch");

        // Auction module also updated
        Auction.Lot memory lotData = _getLotData(_lotId);
        assertEq(lotData.start, _startTime, "start mismatch");
    }

    function test_whenBaseAndQuoteTokenSame()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Update routing params
        _routingParams.quoteToken = _baseToken;

        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(address(routing.baseToken), address(_baseToken), "base token mismatch");
        assertEq(address(routing.quoteToken), address(_baseToken), "quote token mismatch");
    }

    // [X] derivatives
    //  [X] reverts when derivative type is sunset
    //  [X] reverts when derivative type is not installed
    //  [X] reverts when derivative type is not a derivative
    //  [X] reverts when derivation validation fails
    //  [X] sets the derivative on the auction lot

    function test_whenDerivativeModuleNotInstalled_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleNotInstalled.selector, _derivativeModuleKeycode, 0
        );
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenDerivativeTypeIncorrect_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Update routing params
        _routingParams.derivativeType = _atomicAuctionModuleKeycode;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenDerivativeTypeIsSunset_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        _auctionHouse.sunsetModule(_derivativeModuleKeycode);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, _derivativeModuleKeycode);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenDerivativeValidationFails_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
    {
        // Expect revert
        _derivativeModule.setValidateFails(true);
        vm.expectRevert("validation error");

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenDerivativeIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(
            fromVeecode(routing.derivativeReference),
            fromVeecode(_derivativeModule.VEECODE()),
            "derivative type mismatch"
        );
    }

    function test_whenDerivativeIsSet_whenDerivativeParamsIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
    {
        // Update routing params
        _routingParams.derivativeParams = abi.encode("derivative params");

        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(
            fromVeecode(routing.derivativeReference),
            fromVeecode(_derivativeModule.VEECODE()),
            "derivative type mismatch"
        );
        assertEq(
            routing.derivativeParams, abi.encode("derivative params"), "derivative params mismatch"
        );
    }

    // [X] callbacks
    //  [X] reverts when the callbacks address is not a contract
    //  [X] sets the callbacks on the auction lot

    function test_whenCallbackIsNotContract_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Update routing params
        _routingParams.callbacks = ICallback(address(0x10));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_success_givenCallbackIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackIsSet
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(address(routing.callbacks), address(_callback), "callback mismatch");

        // Check that the callback was called
        (address baseToken_, address quoteToken_) = _callback.lotTokens(_lotId);
        assertEq(baseToken_, address(_baseToken), "base token mismatch");
        assertEq(quoteToken_, address(_quoteToken), "quote token mismatch");
    }

    // [X] given the auction is prefunded
    //  [X] when the auction has capacity in quote
    //   [X] reverts
    //  [X] when the auction has callbacks with the send base tokens flag
    //   [X] reverts when the callback does not transfer enough payout tokens
    //   [X] it succeeds
    //  [X] when the auction has callbacks without the send base tokens flag
    //   [X] reverts when the seller does not have enough balance
    //   [X] reverts when the seller does not have enough allowance
    //   [X] it succeeds
    //  [X] when the auction does not have callbacks
    //   [X] reverts when the seller does not have enough balance
    //   [X] reverts when the seller does not have enough allowance
    //   [X] it succeeds

    modifier whenAuctionCapacityInQuote() {
        _auctionParams.capacityInQuote = true;
        _;
    }

    modifier givenOnCreateCallbackBreaksInvariant() {
        _callback.setOnCreateMultiplier(9000);
        _;
    }

    modifier givenBaseTokenTakesFeeOnTransfer() {
        // Set the fee on transfer
        _baseToken.setTransferFee(1000);
        _;
    }

    function test_prefunding_capacityInQuote_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        whenAuctionCapacityInQuote
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_givenCallback_givenSendBaseTokensFlag_invariantBreaks_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenOnCreateCallbackBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidCallback.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_givenCallback_givenSendBaseTokensFlag_feeOnTransfer_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidCallback.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_givenCallback_givenSendBaseTokensFlag()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the funding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, _LOT_CAPACITY, "funding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller balance mismatch");
        assertEq(_baseToken.balanceOf(address(_callback)), 0, "callback balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY,
            "auction house balance mismatch"
        );

        // Check that the callback was called
        (address baseToken_, address quoteToken_) = _callback.lotTokens(_lotId);
        assertEq(baseToken_, address(_baseToken), "base token mismatch");
        assertEq(quoteToken_, address(_quoteToken), "quote token mismatch");
    }

    function test_prefunding_givenCallback_givenSendBaseTokensFlag_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenCallbackHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the funding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, _scaleBaseTokenAmount(_LOT_CAPACITY), "funding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(_callback)), 0, "callback balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance mismatch"
        );

        // Check that the callback was called
        (address baseToken_, address quoteToken_) = _callback.lotTokens(_lotId);
        assertEq(baseToken_, address(_baseToken), "base token mismatch");
        assertEq(quoteToken_, address(_quoteToken), "quote token mismatch");
    }

    function test_prefunding_givenCallback_givenSendBaseTokensFlag_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenCallbackHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the funding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, _scaleBaseTokenAmount(_LOT_CAPACITY), "funding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(_callback)), 0, "callback balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance mismatch"
        );

        // Check that the callback was called
        (address baseToken_, address quoteToken_) = _callback.lotTokens(_lotId);
        assertEq(baseToken_, address(_baseToken), "base token mismatch");
        assertEq(quoteToken_, address(_quoteToken), "quote token mismatch");
    }

    function test_prefunding_givenCallback_insufficientBalance_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackIsSet
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_givenCallback_insufficientAllowance_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_givenCallback_feeOnTransfer_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(_baseToken));
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_givenCallback()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the funding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, _LOT_CAPACITY, "funding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller balance mismatch");
        assertEq(_baseToken.balanceOf(address(_callback)), 0, "callback balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY,
            "auction house balance mismatch"
        );

        // Check that the callback was called
        (address baseToken_, address quoteToken_) = _callback.lotTokens(_lotId);
        assertEq(baseToken_, address(_baseToken), "base token mismatch");
        assertEq(quoteToken_, address(_quoteToken), "quote token mismatch");
    }

    function test_prefunding_insufficientBalance_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_insufficientAllowance_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_feeOnTransfer_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(_baseToken));
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the funding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, _LOT_CAPACITY, "funding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(this)), 0, "seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY,
            "auction house balance mismatch"
        );
    }

    function test_prefunding_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the funding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, _scaleBaseTokenAmount(_LOT_CAPACITY), "funding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(this)), 0, "seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance mismatch"
        );
    }

    function test_prefunding_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the funding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, _scaleBaseTokenAmount(_LOT_CAPACITY), "funding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(this)), 0, "seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance mismatch"
        );
    }
}
