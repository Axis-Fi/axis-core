// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAuctionModule} from "test/modules/Auction/MockAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/Derivative/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";

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

contract AuctionTest is Test {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAuctionModule internal mockAuctionModule;
    MockDerivativeModule internal mockDerivativeModule;
    MockCondenserModule internal mockCondenserModule;

    AuctionHouse internal auctionHouse;
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse();
        mockAuctionModule = new MockAuctionModule(address(auctionHouse));
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockCondenserModule = new MockCondenserModule(address(auctionHouse));

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: 10e18,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("MOCK"),
            baseToken: baseToken,
            quoteToken: quoteToken,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            payoutData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            condenserType: toKeycode("")
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

    modifier whenCondenserModuleIsInstalled() {
        auctionHouse.installModule(mockCondenserModule);
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
    // [X] stores the auction lot
    // [X] derivatives
    //  [X] reverts when derivative type is sunset
    //  [X] reverts when derivative type is not installed
    //  [X] reverts when derivative type is not a derivative
    //  [X] reverts when derivation validation fails
    //  [X] sets the derivative on the auction lot
    // [ ] allowlist
    //  [ ] reverts when allowlist validation fails
    //  [ ] sets the allowlist on the auction lot
    // [X] condenser
    //  [X] reverts when condenser type is sunset
    //  [X] reverts when condenser type is not installed
    //  [X] reverts when condenser type is not a condenser
    //  [ ] reverts when compatibility check fails
    //  [X] sets the condenser on the auction lot
    // [ ] hooks
    //  [ ] sets the hooks on the auction lot

    function testReverts_whenModuleNotInstalled() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 0);
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

        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidType.selector,
            Module.Type.Auction,
            Module.Type.Derivative
        );
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenModuleIsSunset() external whenAuctionModuleIsInstalled {
        // Sunset the module, which prevents the creation of new auctions using that module
        auctionHouse.sunsetModule(toKeycode("MOCK"));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, toKeycode("MOCK"));
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
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidTokenDecimals.selector, address(token), decimals
        );
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
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidTokenDecimals.selector, address(token), decimals
        );
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenBaseTokenIsZero() external whenAuctionModuleIsInstalled {
        routingParams.baseToken = ERC20(address(0));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Auctioneer.Auctioneer_Params_InvalidToken.selector, address(0));
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenQuoteTokenIsZero() external whenAuctionModuleIsInstalled {
        routingParams.quoteToken = ERC20(address(0));

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Auctioneer.Auctioneer_Params_InvalidToken.selector, address(0));
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_success() external whenAuctionModuleIsInstalled {
        // Create the auction
        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

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
            Veecode lotCondenserType
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
        assertEq(fromVeecode(lotCondenserType), "", "condenser type mismatch");

        // Auction module also updated
        (uint48 lotStart,,,,,) = mockAuctionModule.lotData(lotId);
        assertEq(lotStart, block.timestamp, "start mismatch");
    }

    function test_whenBaseAndQuoteTokenSame() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.quoteToken = baseToken;

        // Create the auction
        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (,, ERC20 lotBaseToken, ERC20 lotQuoteToken,,,,,,) = auctionHouse.lotRouting(lotId);
        assertEq(address(lotBaseToken), address(baseToken), "base token mismatch");
        assertEq(address(lotQuoteToken), address(baseToken), "quote token mismatch");
    }

    function testReverts_whenDerivativeModuleNotInstalled() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.derivativeType = toKeycode("DERV");

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("DERV"), 0);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenDerivativeTypeIncorrect() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.derivativeType = toKeycode("MOCK");

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidType.selector,
            Module.Type.Derivative,
            Module.Type.Auction
        );
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenDerivativeTypeIsSunset()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        auctionHouse.sunsetModule(toKeycode("DERV"));

        // Update routing params
        routingParams.derivativeType = toKeycode("DERV");

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
    {
        // Update routing params
        routingParams.derivativeType = toKeycode("DERV");

        // Expect revert
        mockDerivativeModule.setValidateFails(true);
        vm.expectRevert("validation error");

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_whenDerivativeIsSet()
        external
        whenAuctionModuleIsInstalled
        whenDerivativeModuleIsInstalled
    {
        // Update routing params
        routingParams.derivativeType = toKeycode("DERV");

        // Create the auction
        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

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
    {
        // Update routing params
        routingParams.derivativeType = toKeycode("DERV");
        routingParams.derivativeParams = abi.encode("derivative params");

        // Create the auction
        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

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

    function testReverts_whenCondenserModuleNotInstalled() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.condenserType = toKeycode("COND");

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("COND"), 0);
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenCondenserTypeIncorrect() external whenAuctionModuleIsInstalled {
        // Update routing params
        routingParams.condenserType = toKeycode("MOCK");

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Auctioneer.Auctioneer_Params_InvalidType.selector,
            Module.Type.Condenser,
            Module.Type.Auction
        );
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function testReverts_whenCondenserTypeIsSunset()
        external
        whenAuctionModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        // Sunset the module, which prevents the creation of new auctions using that module
        auctionHouse.sunsetModule(toKeycode("COND"));

        // Update routing params
        routingParams.condenserType = toKeycode("COND");

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleIsSunset.selector, toKeycode("COND"));
        vm.expectRevert(err);

        auctionHouse.auction(routingParams, auctionParams);
    }

    function test_whenCondenserIsSet()
        external
        whenAuctionModuleIsInstalled
        whenCondenserModuleIsInstalled
    {
        // Update routing params
        routingParams.condenserType = toKeycode("COND");

        // Create the auction
        uint256 lotId = auctionHouse.auction(routingParams, auctionParams);

        // Assert values
        (,,,,,,,,, Veecode lotCondenserType) = auctionHouse.lotRouting(lotId);
        assertEq(
            fromVeecode(lotCondenserType),
            fromVeecode(mockCondenserModule.VEECODE()),
            "condenser type mismatch"
        );
    }
}
