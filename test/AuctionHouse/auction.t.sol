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
import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Veecode, WithModules, wrapVeecode, fromVeecode} from "src/modules/Modules.sol";

contract AuctionTest is AuctionHouseTest {
    // Imported events
    event AuctionCreated(uint96 indexed _lotId, Veecode indexed auctionRef, string infoHash);

    modifier whenCondenserModuleIsInstalled() {
        _auctionHouse.installModule(_condenserModule);
        _;
    }

    modifier whenCondenserIsMapped() {
        _auctionHouse.setCondenser(
            _atomicAuctionModule.VEECODE(), _derivativeModule.VEECODE(), _condenserModule.VEECODE()
        );
        _;
    }

    // auction
    // [X] reverts when auction module is sunset
    // [X] reverts when auction module is not installed
    // [X] reverts when auction type is not auction
    // [X] reverts when base token decimals are out of bounds
    // [X] reverts when quote token decimals are out of bounds
    // [X] reverts when base token is 0
    // [X] reverts when quote token is 0
    // [X] creates the auction lot

    function testReverts_whenModuleNotInstalled() external whenAuctionTypeIsAtomic {
        bytes memory err = abi.encodeWithSelector(
            WithModules.ModuleNotInstalled.selector, _atomicAuctionModuleKeycode, 0
        );
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenModuleTypeIncorrect()
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

    function testReverts_whenModuleIsSunset()
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

    function testReverts_whenBaseTokenDecimalsAreOutOfBounds(uint8 decimals_)
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

    function testReverts_whenQuoteTokenDecimalsAreOutOfBounds(uint8 decimals_)
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

    function testReverts_whenBaseTokenIsZero()
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

    function testReverts_whenQuoteTokenIsZero()
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
        assertEq(address(routing.hooks), address(0), "hooks mismatch");
        assertEq(address(routing.allowlist), address(0), "allowlist mismatch");
        assertEq(fromVeecode(routing.derivativeReference), "", "derivative type mismatch");
        assertEq(routing.derivativeParams, "", "derivative params mismatch");
        assertEq(routing.wrapDerivative, false, "wrap derivative mismatch");
        assertEq(routing.prefunding, 0, "prefunding mismatch");

        // Curation updated
        Auctioneer.Curation memory curation = _getLotCuration(_lotId);
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

    function testReverts_whenDerivativeModuleNotInstalled()
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

    function testReverts_whenDerivativeTypeIncorrect()
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

    function testReverts_whenDerivativeTypeIsSunset()
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

    function testReverts_whenDerivativeValidationFails()
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

    // [X] condenser
    //  [X] reverts when condenser type is sunset
    //  [X] reverts when compatibility check fails
    //  [X] sets the condenser on the auction lot

    function testReverts_whenCondenserTypeIsSunset()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
        whenDerivativeModuleIsInstalled
        whenCondenserModuleIsInstalled
        whenCondenserIsMapped
    {
        // Sunset the module, which prevents the creation of new auctions using that module
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

    // [X] allowlist
    //  [X] reverts when the allowlist address is not a contract
    //  [X] reverts when allowlist validation fails
    //  [X] sets the allowlist on the auction lot

    modifier whenAllowlistIsSet() {
        // Update routing params
        _routingParams.allowlist = _allowlist;
        _;
    }

    function test_success_allowlistIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenAllowlistIsSet
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(address(routing.allowlist), address(_allowlist), "allowlist mismatch");

        // Check that it has been registered with the allowlist
        uint256[] memory registeredIds = _allowlist.getRegisteredIds();
        assertEq(registeredIds.length, 1, "registered ids length mismatch");
        assertEq(registeredIds[0], _lotId, "registered id mismatch");
    }

    function testReverts_whenAllowlistIsNotContract()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Update routing params
        _routingParams.allowlist = IAllowlist(address(0x10));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenAllowlistValidationFails()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Update routing params
        _routingParams.allowlist = _allowlist;

        // Expect revert
        _allowlist.setRegisterReverts(true);
        vm.expectRevert("MockAllowlist: register reverted");

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    // [X] hooks
    //  [X] reverts when the hooks address is not a contract
    //  [X] sets the hooks on the auction lot

    modifier whenHooksIsSet() {
        // Update routing params
        _routingParams.hooks = _hook;
        _;
    }

    function testReverts_whenHooksIsNotContract()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
    {
        // Update routing params
        _routingParams.hooks = IHooks(address(0x10));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_success_hooksIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenHooksIsSet
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(address(routing.hooks), address(_hook), "hooks mismatch");
    }

    // [X] given the auction module requires prefunding
    //  [X] reverts when the auction has capacity in quote
    //  [X] when the auction has hooks
    //   [X] reverts when the hook does not transfer enough payout tokens
    //   [X] it succeeds
    //  [X] when the auction does not have hooks
    //   [X] reverts when the seller does not have enough balance
    //   [X] reverts when the seller does not have enough allowance
    //   [X] it succeeds

    modifier whenAuctionCapacityInQuote() {
        _auctionParams.capacityInQuote = true;
        _;
    }

    modifier givenPreAuctionCreateHookBreaksInvariant() {
        _hook.setPreAuctionCreateMultiplier(9000);
        _;
    }

    modifier givenBaseTokenTakesFeeOnTransfer() {
        // Set the fee on transfer
        _baseToken.setTransferFee(1000);
        _;
    }

    function test_prefunding_capacityInQuote_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAtomicAuctionRequiresPrefunding
        whenAuctionCapacityInQuote
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_withHooks_invariantBreaks_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenHooksIsSet
        givenAtomicAuctionRequiresPrefunding
        givenHookHasBaseTokenBalance(_LOT_CAPACITY)
        givenPreAuctionCreateHookBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_withHooks_feeOnTransfer_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenHooksIsSet
        givenAtomicAuctionRequiresPrefunding
        givenHookHasBaseTokenBalance(_LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_withHooks()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenHooksIsSet
        givenAtomicAuctionRequiresPrefunding
        givenHookHasBaseTokenBalance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the prefunding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.prefunding, _LOT_CAPACITY, "prefunding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "hook balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY,
            "auction house balance mismatch"
        );
    }

    function test_prefunding_withHooks_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenHooksIsSet
        givenAtomicAuctionRequiresPrefunding
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenHookHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the prefunding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.prefunding, _scaleBaseTokenAmount(_LOT_CAPACITY), "prefunding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "hook balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance mismatch"
        );
    }

    function test_prefunding_withHooks_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        whenHooksIsSet
        givenAtomicAuctionRequiresPrefunding
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenHookHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the prefunding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.prefunding, _scaleBaseTokenAmount(_LOT_CAPACITY), "prefunding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(_hook)), 0, "hook balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance mismatch"
        );
    }

    function test_prefunding_insufficientBalance_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAtomicAuctionRequiresPrefunding
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_insufficientAllowance_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAtomicAuctionRequiresPrefunding
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(_SELLER);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_feeOnTransfer_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAtomicAuctionRequiresPrefunding
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
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAtomicAuctionRequiresPrefunding
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the prefunding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.prefunding, _LOT_CAPACITY, "prefunding mismatch");

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
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAtomicAuctionRequiresPrefunding
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the prefunding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.prefunding, _scaleBaseTokenAmount(_LOT_CAPACITY), "prefunding mismatch");

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
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAtomicAuctionRequiresPrefunding
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
    {
        // Create the auction
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check the prefunding status
        Auctioneer.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.prefunding, _scaleBaseTokenAmount(_LOT_CAPACITY), "prefunding mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(this)), 0, "seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance mismatch"
        );
    }
}
