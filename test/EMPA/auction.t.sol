// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";

// Auctions
import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

// Modules
import {toKeycode, fromVeecode, WithModules} from "src/modules/Modules.sol";

contract EmpaAuctionTest is EmpaTest {
    event AuctionCreated(uint96 indexed _lotId, string infoHash);

    // auction
    // [X] reverts when base token decimals are out of bounds
    // [X] reverts when quote token decimals are out of bounds
    // [X] reverts when base token is 0
    // [X] reverts when quote token is 0
    // [X] creates the auction lot

    function testReverts_whenBaseTokenDecimalsAreOutOfBounds(uint8 decimals_) external {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        _setBaseTokenDecimals(decimals);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenQuoteTokenDecimalsAreOutOfBounds(uint8 decimals_) external {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        _setBaseTokenDecimals(decimals);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenBaseTokenIsZero() external {
        _routingParams.baseToken = ERC20(address(0));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenQuoteTokenIsZero() external {
        _routingParams.quoteToken = ERC20(address(0));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenBaseAndQuoteTokenSame()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Update routing params
        _routingParams.quoteToken = _baseToken;

        // Create the auction
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(address(lotRouting.baseToken), address(_baseToken), "base token mismatch");
        assertEq(address(lotRouting.quoteToken), address(_baseToken), "quote token mismatch");
    }

    // [X] derivatives
    //  [X] reverts when derivative type is sunset
    //  [X] reverts when derivative type is not installed
    //  [X] reverts when derivative type is not a derivative
    //  [X] reverts when derivation validation fails
    //  [X] sets the derivative on the auction lot

    function testReverts_whenDerivativeModuleNotInstalled() external whenDerivativeTypeIsSet {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("DERV"), 0);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenDerivativeTypeIncorrect() external {
        // Install a module that is not a derivative
        MockAtomicAuctionModule mockAtomicModule =
            new MockAtomicAuctionModule(address(_auctionHouse));
        _auctionHouse.installModule(mockAtomicModule);

        // Update routing params
        _routingParams.derivativeType = toKeycode("ATOM");

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenDerivativeTypeIsSunset()
        external
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        _auctionHouse.sunsetModule(toKeycode("DERV"));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, toKeycode("DERV"));
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenDerivativeValidationFails()
        external
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Expect revert
        _mockDerivativeModule.setValidateFails(true);
        vm.expectRevert("validation error");

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_whenDerivativeIsSet()
        external
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            fromVeecode(lotRouting.derivativeReference),
            fromVeecode(_mockDerivativeModule.VEECODE()),
            "derivative type mismatch"
        );
    }

    function test_whenDerivativeIsSet_whenDerivativeParamsIsSet()
        external
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Update routing params
        _routingParams.derivativeParams = abi.encode("derivative params");

        // Create the auction
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            fromVeecode(lotRouting.derivativeReference),
            fromVeecode(_mockDerivativeModule.VEECODE()),
            "derivative type mismatch"
        );
        assertEq(
            lotRouting.derivativeParams,
            abi.encode("derivative params"),
            "derivative params mismatch"
        );
    }

    // [X] allowlist
    //  [X] reverts when the allowlist address is not a contract
    //  [X] reverts when allowlist validation fails
    //  [X] sets the allowlist on the auction lot

    function test_success_allowlistIsSet()
        external
        whenAllowlistIsSet
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);

        assertEq(address(lotRouting.allowlist), address(_mockAllowlist), "allowlist mismatch");

        // Check that it has been registered with the allowlist
        uint256[] memory registeredIds = _mockAllowlist.getRegisteredIds();
        assertEq(registeredIds.length, 1, "registered ids length mismatch");
        assertEq(registeredIds[0], _lotId, "registered id mismatch");
    }

    function testReverts_whenAllowlistIsNotContract() external {
        // Update routing params
        _routingParams.allowlist = IAllowlist(address(0x10));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function testReverts_whenAllowlistValidationFails() external {
        // Update routing params
        _routingParams.allowlist = _mockAllowlist;

        // Expect revert
        _mockAllowlist.setRegisterReverts(true);
        vm.expectRevert("MockAllowlist: register reverted");

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    // [X] hooks
    //  [X] reverts when the hooks address is not a contract
    //  [X] sets the hooks on the auction lot

    function testReverts_whenHooksIsNotContract() external {
        // Update routing params
        _routingParams.hooks = IHooks(address(0x10));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_success_hooksIsSet()
        external
        whenHooksIsSet
        givenHookHasBaseTokenBalance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);

        assertEq(address(lotRouting.hooks), address(_mockHook), "hooks mismatch");
    }

    // [X] given the auction module requires prefunding
    //  [X] when the auction has hooks
    //   [X] reverts when the hook does not transfer enough payout tokens
    //   [X] it succeeds
    //  [X] when the auction does not have hooks
    //   [X] reverts when the auction owner does not have enough balance
    //   [X] reverts when the auction owner does not have enough allowance
    //   [X] it succeeds

    modifier givenPreAuctionCreateHookBreaksInvariant() {
        _mockHook.setPreAuctionCreateMultiplier(9000);
        _;
    }

    modifier givenBaseTokenTakesFeeOnTransfer() {
        // Set the fee on transfer
        _baseToken.setTransferFee(1000);
        _;
    }

    function test_prefunding_withHooks_invariantBreaks_reverts()
        external
        whenHooksIsSet
        givenHookHasBaseTokenBalance(_LOT_CAPACITY)
        givenPreAuctionCreateHookBreaksInvariant
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidHook.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_withHooks_feeOnTransfer_reverts()
        external
        whenHooksIsSet
        givenHookHasBaseTokenBalance(_LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidHook.selector);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_withHooks()
        external
        whenHooksIsSet
        givenHookHasBaseTokenBalance(_LOT_CAPACITY)
    {
        // Create the auction
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Check that the hook is set
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(address(lotRouting.hooks), address(_mockHook), "hooks mismatch");

        // Check balances
        assertEq(_baseToken.balanceOf(address(_mockHook)), 0, "hook balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY,
            "auction house balance mismatch"
        );
    }

    function test_prefunding_insufficientBalance_reverts()
        external
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_insufficientAllowance_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding_feeOnTransfer_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(_baseToken));
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
    }

    function test_prefunding()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
    {
        // Expect event to be emitted
        vm.expectEmit(address(_auctionHouse));
        emit AuctionCreated(0, _INFO_HASH);

        // Create the auction
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.owner, _auctionOwner, "owner mismatch");
        assertEq(address(lotRouting.baseToken), address(_baseToken), "base token mismatch");
        assertEq(address(lotRouting.quoteToken), address(_quoteToken), "quote token mismatch");
        assertEq(lotRouting.curator, _CURATOR, "curator mismatch");
        assertEq(lotRouting.curated, false, "curated mismatch");
        assertEq(lotRouting.curatorFee, 0, "curator fee mismatch");
        assertEq(address(lotRouting.hooks), address(0), "hooks mismatch");
        assertEq(address(lotRouting.allowlist), address(0), "allowlist mismatch");
        assertEq(fromVeecode(lotRouting.derivativeReference), "", "derivative type mismatch");
        assertEq(lotRouting.wrapDerivative, false, "wrap derivative mismatch");
        assertEq(lotRouting.derivativeParams, "", "derivative params mismatch");

        // Auction module also updated
        EncryptedMarginalPriceAuction.Lot memory lotData = _getLotData(_lotId);
        assertEq(lotData.minimumPrice, _MIN_PRICE, "minimum price mismatch");
        assertEq(lotData.capacity, _LOT_CAPACITY, "capacity mismatch");
        assertEq(
            lotData.quoteTokenDecimals, _quoteToken.decimals(), "quote token decimals mismatch"
        );
        assertEq(lotData.baseTokenDecimals, _baseToken.decimals(), "base token decimals mismatch");
        assertEq(lotData.start, _startTime, "start mismatch");
        assertEq(lotData.conclusion, _startTime + _duration, "conclusion mismatch");
        assertEq(
            uint8(lotData.status),
            uint8(EncryptedMarginalPriceAuction.AuctionStatus.Created),
            "status mismatch"
        );
        assertEq(lotData.minFilled, _LOT_CAPACITY * _MIN_FILL_PERCENT / 1e5, "min filled mismatch");
        assertEq(
            lotData.minBidSize, _LOT_CAPACITY * _MIN_BID_PERCENT / 1e5, "min bid size mismatch"
        );

        // Check balances
        assertEq(_baseToken.balanceOf(address(this)), 0, "owner balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY,
            "auction house balance mismatch"
        );
    }
}
