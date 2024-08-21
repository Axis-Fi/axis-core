// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {AtomicAuctionHouseTest} from "./AuctionHouseTest.sol";

// Mocks
import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";
import {MockBatchAuctionModule} from "../modules/Auction/MockBatchAuctionModule.sol";

import {IAuctionHouse} from "../../src/interfaces/IAuctionHouse.sol";
import {IAuction} from "../../src/interfaces/modules/IAuction.sol";
import {ICallback} from "../../src/interfaces/ICallback.sol";
import {
    Keycode,
    keycodeFromVeecode,
    Veecode,
    WithModules,
    wrapVeecode,
    fromVeecode
} from "../../src/modules/Modules.sol";

contract AtomicCreateAuctionTest is AtomicAuctionHouseTest {
    MockBatchAuctionModule internal _batchAuctionModule;
    Keycode internal _batchAuctionModuleKeycode;

    // Imported events
    event AuctionCreated(uint96 indexed _lotId, Veecode indexed auctionRef, string infoHash);

    // ======= Modifiers =======//

    modifier whenAuctionTypeIsBatch() {
        _batchAuctionModule = new MockBatchAuctionModule(address(_auctionHouse));
        _batchAuctionModuleKeycode = keycodeFromVeecode(_batchAuctionModule.VEECODE());

        _routingParams.auctionType = _batchAuctionModuleKeycode;

        _auctionModule = _batchAuctionModule;
        _auctionModuleKeycode = _batchAuctionModuleKeycode;
        _;
    }

    modifier whenBatchAuctionModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_batchAuctionModule);
        _;
    }

    // ======= Tests ======= //

    // auction
    // [X] reverts when auction module is sunset
    // [X] reverts when auction module is not installed
    // [X] reverts when auction type is not the keycode of an auction module
    // [X] when the auction type is batch
    // [X] reverts when base token decimals are out of bounds
    // [X] reverts when quote token decimals are out of bounds
    // [X] reverts when base token is 0
    // [X] reverts when quote token is 0
    // [X] creates the auction lot
    // [X] creates multiple auction lots

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

        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenAuctionTypeIncorrect_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        // Set the auction type to a derivative module
        _routingParams.auctionType = _batchAuctionModuleKeycode;

        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
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
        vm.prank(_OWNER);
        _auctionHouse.sunsetModule(_atomicAuctionModuleKeycode);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, _atomicAuctionModuleKeycode);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenBaseTokenDecimalsAreOutOfBounds_reverts(
        uint8 decimals_
    ) external whenAuctionTypeIsAtomic whenAtomicAuctionModuleIsInstalled {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        // Create a token with the decimals
        MockERC20 token = new MockERC20("Token", "TOK", decimals);

        // Update routing params
        _routingParams.baseToken = address(token);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenQuoteTokenDecimalsAreOutOfBounds_reverts(
        uint8 decimals_
    ) external whenAuctionTypeIsAtomic whenAtomicAuctionModuleIsInstalled {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        // Create a token with the decimals
        MockERC20 token = new MockERC20("Token", "TOK", decimals);

        // Update routing params
        _routingParams.quoteToken = address(token);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenBaseTokenIsZero_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        _routingParams.baseToken = address(0);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenQuoteTokenIsZero_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        _routingParams.quoteToken = address(0);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
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
        IAuctionHouse.Routing memory routing = _getLotRouting(_lotId);
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
        IAuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator mismatch");
        assertEq(curation.curated, false, "curated mismatch");

        // Auction module also updated
        IAuction.Lot memory lotData = _getLotData(_lotId);
        assertEq(lotData.start, _startTime, "start mismatch");
    }

    function test_success_multiple()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Create the first auction
        vm.prank(_SELLER);
        uint96 lotIdOne = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Expect event to be emitted
        vm.expectEmit(address(_auctionHouse));
        emit AuctionCreated(1, wrapVeecode(_routingParams.auctionType, 1), _INFO_HASH);

        // Modify the parameters
        _routingParams.baseToken = address(_quoteToken);
        _routingParams.quoteToken = address(_baseToken);
        _auctionParams.start = _startTime + 1;

        // Create the second auction
        vm.prank(_SELLER);
        uint96 lotIdTwo = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values for lot one
        IAuctionHouse.Routing memory routing = _getLotRouting(lotIdOne);
        assertEq(address(routing.baseToken), address(_baseToken), "lot one: base token mismatch");
        assertEq(address(routing.quoteToken), address(_quoteToken), "lot one: quote token mismatch");
        IAuction.Lot memory lotData = _getLotData(lotIdOne);
        assertEq(lotData.start, _startTime, "lot one: start mismatch");

        // Assert values for lot two
        routing = _getLotRouting(lotIdTwo);
        assertEq(address(routing.baseToken), address(_quoteToken), "lot two: base token mismatch");
        assertEq(address(routing.quoteToken), address(_baseToken), "lot two: quote token mismatch");
        lotData = _getLotData(lotIdTwo);
        assertEq(lotData.start, _startTime + 1, "lot two: start mismatch");
    }

    function test_whenBaseAndQuoteTokenSame()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Update routing params
        _routingParams.quoteToken = address(_baseToken);

        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        IAuctionHouse.Routing memory routing = _getLotRouting(_lotId);
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
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
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
        vm.prank(_OWNER);
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
        IAuctionHouse.Routing memory routing = _getLotRouting(_lotId);
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
        IAuctionHouse.Routing memory routing = _getLotRouting(_lotId);
        assertEq(
            fromVeecode(routing.derivativeReference),
            fromVeecode(_derivativeModule.VEECODE()),
            "derivative type mismatch"
        );
        assertEq(
            routing.derivativeParams, abi.encode("derivative params"), "derivative params mismatch"
        );
    }

    // [X] condenser
    //  [X] reverts when condenser type is sunset
    //  [X] sets the condenser on the auction lot

    function test_whenCondenserTypeIsSunset_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
        whenCondenserIsMapped
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        vm.prank(_OWNER);
        _auctionHouse.sunsetModule(_condenserModuleKeycode);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, _condenserModuleKeycode);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenCondenserIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
        whenCondenserIsMapped
    {
        // Create the auction
        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Won't revert
    }

    function test_whenCondenserIsNotSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        // Create the auction
        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Won't revert
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
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidParams.selector);
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
        IAuctionHouse.Routing memory routing = _getLotRouting(_lotId);
        assertEq(address(routing.callbacks), address(_callback), "callback mismatch");

        // Check that the callback was called
        (address baseToken_, address quoteToken_) = _callback.lotTokens(_lotId);
        assertEq(baseToken_, address(_baseToken), "base token mismatch");
        assertEq(quoteToken_, address(_quoteToken), "quote token mismatch");
    }
}
