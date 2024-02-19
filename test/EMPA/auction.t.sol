// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {Point, ECIES} from "src/lib/ECIES.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {MockHook} from "test/modules/Auction/MockHook.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

// Modules
import {
    Keycode,
    toKeycode,
    Veecode,
    wrapVeecode,
    fromVeecode,
    WithModules,
    Module
} from "src/modules/Modules.sol";

import {EMPATest} from "test/EMPA/EMPATest.sol";

contract EMPA_AuctionTest is EMPATest {
    event AuctionCreated(uint96 indexed lotId, string infoHash);

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

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function testReverts_whenQuoteTokenDecimalsAreOutOfBounds(uint8 decimals_) external {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        _setBaseTokenDecimals(decimals);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function testReverts_whenBaseTokenIsZero() external {
        routingParams.baseToken = ERC20(address(0));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function testReverts_whenQuoteTokenIsZero() external {
        routingParams.quoteToken = ERC20(address(0));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function test_whenBaseAndQuoteTokenSame()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(LOT_CAPACITY)
    {
        // Update routing params
        routingParams.quoteToken = baseToken;

        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams, INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(lotId);
        assertEq(address(lotRouting.baseToken), address(baseToken), "base token mismatch");
        assertEq(address(lotRouting.quoteToken), address(quoteToken), "quote token mismatch");
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

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function testReverts_whenDerivativeTypeIncorrect() external {
        // Update routing params
        routingParams.derivativeType = toKeycode("ATOM");

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function testReverts_whenDerivativeTypeIsSunset()
        external
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        auctionHouse.sunsetModule(toKeycode("DERV"));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, toKeycode("DERV"));
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function testReverts_whenDerivativeValidationFails()
        external
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Expect revert
        mockDerivativeModule.setValidateFails(true);
        vm.expectRevert("validation error");

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function test_whenDerivativeIsSet()
        external
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams, INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(lotId);
        assertEq(
            fromVeecode(lotRouting.derivativeReference),
            fromVeecode(mockDerivativeModule.VEECODE()),
            "derivative type mismatch"
        );
    }

    function test_whenDerivativeIsSet_whenDerivativeParamsIsSet()
        external
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Update routing params
        routingParams.derivativeParams = abi.encode("derivative params");

        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams, INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(lotId);
        assertEq(
            fromVeecode(lotRouting.derivativeReference),
            fromVeecode(mockDerivativeModule.VEECODE()),
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
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(LOT_CAPACITY)
    {
        // Create the auction
        lotId = auctionHouse.auction(routingParams, auctionParams, INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(lotId);

        assertEq(address(lotRouting.allowlist), address(mockAllowlist), "allowlist mismatch");

        // Check that it has been registered with the allowlist
        uint256[] memory registeredIds = mockAllowlist.getRegisteredIds();
        assertEq(registeredIds.length, 1, "registered ids length mismatch");
        assertEq(registeredIds[0], lotId, "registered id mismatch");
    }

    function testReverts_whenAllowlistIsNotContract() external {
        // Update routing params
        routingParams.allowlist = IAllowlist(address(0x10));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function testReverts_whenAllowlistValidationFails() external {
        // Update routing params
        routingParams.allowlist = mockAllowlist;

        // Expect revert
        mockAllowlist.setRegisterReverts(true);
        vm.expectRevert("MockAllowlist: register reverted");

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    // [X] hooks
    //  [X] reverts when the hooks address is not a contract
    //  [X] sets the hooks on the auction lot

    function testReverts_whenHooksIsNotContract() external {
        // Update routing params
        routingParams.hooks = IHooks(address(0x10));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function test_success_hooksIsSet() external whenHooksIsSet {
        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams, INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(lotId);

        assertEq(address(lotRouting.hooks), address(mockHook), "hooks mismatch");
    }

    // [X] given the auction module requires prefunding
    //  [X] when the auction has hooks
    //   [X] reverts when the hook does not transfer enough payout tokens
    //   [X] it succeeds
    //  [X] when the auction does not have hooks
    //   [X] reverts when the auction owner does not have enough balance
    //   [X] reverts when the auction owner does not have enough allowance
    //   [X] it succeeds

    modifier givenHookHasBaseTokenBalance(uint256 amount_) {
        // Mint the amount to the hook
        baseToken.mint(address(mockHook), amount_);
        _;
    }

    modifier givenPreAuctionCreateHookBreaksInvariant() {
        mockHook.setPreAuctionCreateMultiplier(9000);
        _;
    }

    modifier givenBaseTokenTakesFeeOnTransfer() {
        // Set the fee on transfer
        baseToken.setTransferFee(1000);
        _;
    }

    function test_prefunding_withHooks_invariantBreaks_reverts()
        external
        whenHooksIsSet
        givenHookHasBaseTokenBalance(LOT_CAPACITY)
        givenPreAuctionCreateHookBreaksInvariant
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidHook.selector);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function test_prefunding_withHooks_feeOnTransfer_reverts()
        external
        whenHooksIsSet
        givenHookHasBaseTokenBalance(LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.InvalidHook.selector);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function test_prefunding_withHooks()
        external
        whenHooksIsSet
        givenHookHasBaseTokenBalance(LOT_CAPACITY)
    {
        // Create the auction
        lotId = auctionHouse.auction(routingParams, auctionParams, INFO_HASH);

        // Check that the hook is set
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(lotId);
        assertEq(address(lotRouting.hooks), address(mockHook), "hooks mismatch");

        // Check balances
        assertEq(baseToken.balanceOf(address(mockHook)), 0, "hook balance mismatch");
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            LOT_CAPACITY,
            "auction house balance mismatch"
        );
    }

    function test_prefunding_insufficientBalance_reverts()
        external
        givenOwnerHasBaseTokenAllowance(LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function test_prefunding_insufficientAllowance_reverts()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function test_prefunding_feeOnTransfer_reverts()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(baseToken));
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
    }

    function test_prefunding()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(LOT_CAPACITY)
    {
        // Expect event to be emitted
        vm.expectEmit(address(auctionHouse));
        emit AuctionCreated(0, INFO_HASH);

        // Create the auction
        lotId = auctionHouse.auction(routingParams, auctionParams, INFO_HASH);

        // Assert values
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(lotId);
        assertEq(lotRouting.owner, address(this), "owner mismatch");
        assertEq(address(lotRouting.baseToken), address(baseToken), "base token mismatch");
        assertEq(address(lotRouting.quoteToken), address(quoteToken), "quote token mismatch");
        assertEq(lotRouting.curator, curator, "curator mismatch");
        assertEq(lotRouting.curated, false, "curated mismatch");
        assertEq(lotRouting.curatorFee, 0, "curator fee mismatch");
        assertEq(address(lotRouting.hooks), address(0), "hooks mismatch");
        assertEq(address(lotRouting.allowlist), address(0), "allowlist mismatch");
        assertEq(fromVeecode(lotRouting.derivativeReference), "", "derivative type mismatch");
        assertEq(lotRouting.wrapDerivative, false, "wrap derivative mismatch");
        assertEq(lotRouting.derivativeParams, "", "derivative params mismatch");

        // Auction module also updated
        EncryptedMarginalPriceAuction.Lot memory lotData = _getLotData(lotId);
        assertEq(lotData.minimumPrice, MIN_PRICE, "minimum price mismatch");
        assertEq(lotData.capacity, LOT_CAPACITY, "capacity mismatch");
        assertEq(lotData.quoteTokenDecimals, quoteToken.decimals(), "quote token decimals mismatch");
        assertEq(lotData.baseTokenDecimals, baseToken.decimals(), "base token decimals mismatch");
        assertEq(lotData.start, startTime, "start mismatch");
        assertEq(lotData.conclusion, startTime + duration, "conclusion mismatch");
        assertEq(
            uint8(lotData.status),
            uint8(EncryptedMarginalPriceAuction.AuctionStatus.Created),
            "status mismatch"
        );
        assertEq(lotData.minFilled, LOT_CAPACITY * MIN_FILL_PERCENT / 1e5, "min filled mismatch");
        assertEq(lotData.minBidSize, LOT_CAPACITY * MIN_BID_PERCENT / 1e5, "min bid size mismatch");

        // Check balances
        assertEq(baseToken.balanceOf(address(this)), 0, "owner balance mismatch");
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            LOT_CAPACITY,
            "auction house balance mismatch"
        );
    }
}
