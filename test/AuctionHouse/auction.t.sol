// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {MockHook} from "test/modules/Auction/MockHook.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {IHooks, IAllowlist, Auctioneer} from "src/bases/Auctioneer.sol";

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

contract AuctionTest is Test, Permit2User {
    MockFeeOnTransferERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAtomicAuctionModule internal mockAuctionModule;
    MockDerivativeModule internal mockDerivativeModule;
    MockCondenserModule internal mockCondenserModule;
    MockAllowlist internal mockAllowlist;
    MockHook internal mockHook;

    AuctionHouse internal auctionHouse;
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    address internal immutable protocol = address(0x2);
    address internal immutable curator = address(0x3);

    uint256 internal constant LOT_CAPACITY = 10e18;

    function setUp() external {
        baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(protocol, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockCondenserModule = new MockCondenserModule(address(auctionHouse));
        mockAllowlist = new MockAllowlist();
        mockHook = new MockHook(address(quoteToken), address(baseToken));

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("ATOM"),
            baseToken: baseToken,
            quoteToken: quoteToken,
            curator: curator,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode("")
        });
    }

    modifier whenAuctionModuleIsInstalled() {
        auctionHouse.installModule(mockAuctionModule);
        _;
    }

    modifier whenDerivativeModuleIsInstalled() {
        auctionHouse.installModule(mockDerivativeModule);
        _;
    }

    modifier whenDerivativeTypeIsSet() {
        routingParams.derivativeType = toKeycode("DERV");
        _;
    }

    modifier whenCondenserModuleIsInstalled() {
        auctionHouse.installModule(mockCondenserModule);
        _;
    }

    modifier whenCondenserIsMapped() {
        auctionHouse.setCondenser(
            mockAuctionModule.VEECODE(),
            mockDerivativeModule.VEECODE(),
            mockCondenserModule.VEECODE()
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

    function testReverts_whenModuleNotInstalled() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("ATOM"), 0);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenModuleTypeIncorrect()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        // Set the auction type to a derivative module
        routingParams.auctionType = toKeycode("DERV");

        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenModuleIsSunset() external whenAuctionModuleIsInstalled {
        // Sunset the module, which prevents the creation of new auctions using that module
        auctionHouse.sunsetModule(toKeycode("ATOM"));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, toKeycode("ATOM"));
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenBaseTokenDecimalsAreOutOfBounds(uint8 decimals_)
        external
        whenAuctionModuleIsInstalled
    {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        // Create a token with the decimals
        MockERC20 token = new MockERC20("Token", "TOK", decimals);

        // Update routing params
        routingParams.baseToken = token;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenQuoteTokenDecimalsAreOutOfBounds(uint8 decimals_)
        external
        whenAuctionModuleIsInstalled
    {
        uint8 decimals = uint8(bound(decimals_, 0, 50));
        vm.assume(decimals < 6 || decimals > 18);

        // Create a token with the decimals
        MockERC20 token = new MockERC20("Token", "TOK", decimals);

        // Update routing params
        routingParams.quoteToken = token;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenBaseTokenIsZero() external whenAuctionModuleIsInstalled {
        routingParams.baseToken = ERC20(address(0));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenQuoteTokenIsZero() external whenAuctionModuleIsInstalled {
        routingParams.quoteToken = ERC20(address(0));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_success() external whenAuctionModuleIsInstalled {
        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (
            Veecode lotAuctionType,
            address lotOwner,
            ERC20 lotBaseToken,
            ERC20 lotQuoteToken,
            IHooks lotHooks,
            IAllowlist lotAllowlist,
            Veecode lotDerivativeType,
            bytes memory lotDerivativeParams,
            bool lotWrapDerivative,
            uint256 lotPrefunding
        ) = auctionHouse.lotRouting(lotId);
        assertEq(
            fromVeecode(lotAuctionType),
            fromVeecode(wrapVeecode(routingParams.auctionType, 1)),
            "auction type mismatch"
        );
        assertEq(lotOwner, address(this), "owner mismatch");
        assertEq(address(lotBaseToken), address(baseToken), "base token mismatch");
        assertEq(address(lotQuoteToken), address(quoteToken), "quote token mismatch");
        assertEq(address(lotHooks), address(0), "hooks mismatch");
        assertEq(address(lotAllowlist), address(0), "allowlist mismatch");
        assertEq(fromVeecode(lotDerivativeType), "", "derivative type mismatch");
        assertEq(lotDerivativeParams, "", "derivative params mismatch");
        assertEq(lotWrapDerivative, false, "wrap derivative mismatch");
        assertEq(lotPrefunding, 0, "prefunding mismatch");

        // Curation updated
        (address lotCurator, bool lotCurated) = auctionHouse.lotCuration(lotId);
        assertEq(lotCurator, curator, "curator mismatch");
        assertEq(lotCurated, false, "curated mismatch");

        // Auction module also updated
        (uint48 lotStart,,,,,,,) = mockAuctionModule.lotData(lotId);
        assertEq(lotStart, block.timestamp, "start mismatch");
    }

    function test_whenBaseAndQuoteTokenSame() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.quoteToken = baseToken;

        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (,, ERC20 lotBaseToken, ERC20 lotQuoteToken,,,,,,) = auctionHouse.lotRouting(lotId);
        assertEq(address(lotBaseToken), address(baseToken), "base token mismatch");
        assertEq(address(lotQuoteToken), address(baseToken), "quote token mismatch");
    }

    // [X] derivatives
    //  [X] reverts when derivative type is sunset
    //  [X] reverts when derivative type is not installed
    //  [X] reverts when derivative type is not a derivative
    //  [X] reverts when derivation validation fails
    //  [X] sets the derivative on the auction lot

    function testReverts_whenDerivativeModuleNotInstalled()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("DERV"), 0);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenDerivativeTypeIncorrect() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.derivativeType = toKeycode("ATOM");

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenDerivativeTypeIsSunset()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        auctionHouse.sunsetModule(toKeycode("DERV"));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, toKeycode("DERV"));
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenDerivativeValidationFails()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Expect revert
        mockDerivativeModule.setValidateFails(true);
        vm.expectRevert("validation error");

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_whenDerivativeIsSet()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (,,,,,, Veecode lotDerivativeType,,,) = auctionHouse.lotRouting(lotId);
        assertEq(
            fromVeecode(lotDerivativeType),
            fromVeecode(mockDerivativeModule.VEECODE()),
            "derivative type mismatch"
        );
    }

    function test_whenDerivativeIsSet_whenDerivativeParamsIsSet()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
    {
        // Update routing params
        routingParams.derivativeParams = abi.encode("derivative params");

        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (,,,,,, Veecode lotDerivativeType, bytes memory lotDerivativeParams,,) =
            auctionHouse.lotRouting(lotId);
        assertEq(
            fromVeecode(lotDerivativeType),
            fromVeecode(mockDerivativeModule.VEECODE()),
            "derivative type mismatch"
        );
        assertEq(lotDerivativeParams, abi.encode("derivative params"), "derivative params mismatch");
    }

    // [X] condenser
    //  [X] reverts when condenser type is sunset
    //  [X] reverts when compatibility check fails
    //  [X] sets the condenser on the auction lot

    function testReverts_whenCondenserTypeIsSunset()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
        whenCondenserModuleIsInstalled
        whenCondenserIsMapped
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        auctionHouse.sunsetModule(toKeycode("COND"));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, toKeycode("COND"));
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_whenCondenserIsSet()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
        whenDerivativeTypeIsSet
        whenCondenserModuleIsInstalled
        whenCondenserIsMapped
    {
        // Create the auction
        auctionHouse.auction(routingParams, auctionParams);

        // Won't revert
    }

    // [X] allowlist
    //  [X] reverts when the allowlist address is not a contract
    //  [X] reverts when allowlist validation fails
    //  [X] sets the allowlist on the auction lot

    modifier whenAllowlistIsSet() {
        // Update routing params
        routingParams.allowlist = mockAllowlist;
        _;
    }

    function test_success_allowlistIsSet()
        external
        whenAuctionModuleIsInstalled
        whenAllowlistIsSet
    {
        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (,,,,, IAllowlist lotAllowlist,,,,) = auctionHouse.lotRouting(lotId);

        assertEq(address(lotAllowlist), address(mockAllowlist), "allowlist mismatch");

        // Check that it has been registered with the allowlist
        uint256[] memory registeredIds = mockAllowlist.getRegisteredIds();
        assertEq(registeredIds.length, 1, "registered ids length mismatch");
        assertEq(registeredIds[0], lotId, "registered id mismatch");
    }

    function testReverts_whenAllowlistIsNotContract() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.allowlist = IAllowlist(address(0x10));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenAllowlistValidationFails() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.allowlist = mockAllowlist;

        // Expect revert
        mockAllowlist.setRegisterReverts(true);
        vm.expectRevert("MockAllowlist: register reverted");

        auctionHouse.auction(routingParams, auctionParams);
    }

    // [X] hooks
    //  [X] reverts when the hooks address is not a contract
    //  [X] sets the hooks on the auction lot

    modifier whenHooksIsSet() {
        // Update routing params
        routingParams.hooks = mockHook;
        _;
    }

    function testReverts_whenHooksIsNotContract() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.hooks = IHooks(address(0x10));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_success_hooksIsSet() external whenAuctionModuleIsInstalled whenHooksIsSet {
        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (,,,, IHooks lotHooks,,,,,) = auctionHouse.lotRouting(lotId);

        assertEq(address(lotHooks), address(mockHook), "hooks mismatch");
    }

    // [X] given the auction module requires prefunding
    //  [X] reverts when the auction has capacity in quote
    //  [X] when the auction has hooks
    //   [X] reverts when the hook does not transfer enough payout tokens
    //   [X] it succeeds
    //  [X] when the auction does not have hooks
    //   [X] reverts when the auction owner does not have enough balance
    //   [X] reverts when the auction owner does not have enough allowance
    //   [X] it succeeds

    modifier givenAuctionRequiresPrefunding() {
        mockAuctionModule.setRequiredPrefunding(true);
        _;
    }

    modifier whenAuctionCapacityInQuote() {
        auctionParams.capacityInQuote = true;
        _;
    }

    modifier givenHookHasBaseTokenBalance(uint256 amount_) {
        // Mint the amount to the hook
        baseToken.mint(address(mockHook), amount_);
        _;
    }

    modifier givenPreAuctionCreateHookBreaksInvariant() {
        mockHook.setPreAuctionCreateMultiplier(9000);
        _;
    }

    modifier givenOwnerHasBaseTokenAllowance(uint256 amount_) {
        // Approve the auction house
        baseToken.approve(address(auctionHouse), amount_);
        _;
    }

    modifier givenOwnerHasBaseTokenBalance(uint256 amount_) {
        // Mint the amount to the owner
        baseToken.mint(address(this), amount_);
        _;
    }

    modifier givenBaseTokenTakesFeeOnTransfer() {
        // Set the fee on transfer
        baseToken.setTransferFee(1000);
        _;
    }

    function test_prefunding_capacityInQuote_reverts()
        external
        whenAuctionModuleIsInstalled
        givenAuctionRequiresPrefunding
        whenAuctionCapacityInQuote
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidParams.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_prefunding_withHooks_invariantBreaks_reverts()
        external
        whenAuctionModuleIsInstalled
        whenHooksIsSet
        givenAuctionRequiresPrefunding
        givenHookHasBaseTokenBalance(LOT_CAPACITY)
        givenPreAuctionCreateHookBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_prefunding_withHooks_feeOnTransfer_reverts()
        external
        whenAuctionModuleIsInstalled
        whenHooksIsSet
        givenAuctionRequiresPrefunding
        givenHookHasBaseTokenBalance(LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidHook.selector);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_prefunding_withHooks()
        external
        whenAuctionModuleIsInstalled
        whenHooksIsSet
        givenAuctionRequiresPrefunding
        givenHookHasBaseTokenBalance(LOT_CAPACITY)
    {
        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Check the prefunding status
        (,,,,,,,,, uint256 lotPrefunding) = auctionHouse.lotRouting(lotId);
        assertEq(lotPrefunding, LOT_CAPACITY, "prefunding mismatch");

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
        whenAuctionModuleIsInstalled
        givenAuctionRequiresPrefunding
        givenOwnerHasBaseTokenAllowance(LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_prefunding_insufficientAllowance_reverts()
        external
        whenAuctionModuleIsInstalled
        givenAuctionRequiresPrefunding
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_prefunding_feeOnTransfer_reverts()
        external
        whenAuctionModuleIsInstalled
        givenAuctionRequiresPrefunding
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(LOT_CAPACITY)
        givenBaseTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(baseToken));
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_prefunding()
        external
        whenAuctionModuleIsInstalled
        givenAuctionRequiresPrefunding
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(LOT_CAPACITY)
    {
        // Create the auction
        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Check the prefunding status
        (,,,,,,,,, uint256 lotPrefunding) = auctionHouse.lotRouting(lotId);
        assertEq(lotPrefunding, LOT_CAPACITY, "prefunding mismatch");

        // Check balances
        assertEq(baseToken.balanceOf(address(this)), 0, "owner balance mismatch");
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            LOT_CAPACITY,
            "auction house balance mismatch"
        );
    }
}
