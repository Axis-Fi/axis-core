// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAuctionModule} from "test/modules/Auction/MockAuctionModule.sol";

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
    WithModules
} from "src/modules/Modules.sol";

contract AuctionTest is Test {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAuctionModule internal mockModule;

    AuctionHouse internal auctionHouse;
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse();
        mockModule = new MockAuctionModule(address(auctionHouse));

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
        auctionHouse.installModule(mockModule);
        _;
    }

    // auction
    // [X] reverts when auction module is sunset
    // [X] reverts when auction module is not installed
    // [X] reverts when base token decimals are out of bounds
    // [X] reverts when quote token decimals are out of bounds
    // [X] reverts when base token is 0
    // [X] reverts when quote token is 0
    // [X] stores the auction lot
    // [ ] derivatives
    //  [ ] reverts when derivative type is sunset
    //  [ ] reverts when derivative type is not installed
    //  [ ] reverts when derivation validation fails
    //  [ ] sets the derivative on the auction lot
    // [ ] allowlist
    //  [ ] reverts when allowlist validation fails
    //  [ ] sets the allowlist on the auction lot
    // [ ] condenser
    //  [ ] reverts when condenser type is sunset
    //  [ ] reverts when condenser type is not installed
    //  [ ] sets the condenser on the auction lot
    // [ ] hooks
    //  [ ] sets the hooks on the auction lot

    function testReverts_whenModuleNotInstalled() external {
        bytes memory err =
            abi.encodeWithSelector(WithModules.ModuleNotInstalled.selector, toKeycode("MOCK"), 0);
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
        (uint48 lotStart,,,,,) = mockModule.lotData(lotId);
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
}
