// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/Derivative/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {MockHook} from "test/modules/Auction/MockHook.sol";

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

contract PurchaseTest is Test {
    MockERC20 internal baseToken;
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

    uint256 internal lotId;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(protocol);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockCondenserModule = new MockCondenserModule(address(auctionHouse));
        mockAllowlist = new MockAllowlist();
        mockHook = new MockHook();

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: 10e18,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("ATOM"),
            baseToken: baseToken,
            quoteToken: quoteToken,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            payoutData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode("")
        });

        // Install the auction module
        auctionHouse.installModule(mockAuctionModule);

        // Create an auction
        lotId = auctionHouse.auction(routingParams, auctionParams);
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

    modifier whenBatchAuctionIsCreated() {
        MockBatchAuctionModule mockBatchAuctionModule =
            new MockBatchAuctionModule(address(auctionHouse));

        // Install the batch auction module
        auctionHouse.installModule(mockBatchAuctionModule);

        // Modify the routing params to create a batch auction
        routingParams.auctionType = toKeycode("BATCH");

        // Create the batch auction
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    // purchase
    // [ ] reverts if the lot id is invalid
    // [ ] reverts if the auction is not atomic
    // [ ] reverts if the auction is not active
    // [ ] reverts if the auction module reverts
    // [ ] reverts if the payout amount is less than the minimum
    // [ ] reverts if the caller does not have sufficient balance of the quote token
    // [ ] reverts if the caller has not approved the Permit2 contract
    // [ ] reverts if the auction owner does not have sufficient balance of the payout token
    // [ ] reverts if there is a callback that fails
    // [ ] reverts if the Permit2 approval is invalid
    // [ ] allowlist
    //  [ ] reverts if the caller is not on the allowlist
    // [ ] derivative
    //  [ ] mints derivative tokens to the recipient
    //  [ ] if specified, uses the condenser
    // [ ] non-derivative
    //  [ ] transfers the base token to the recipient
    // [ ] fees
    //  [ ] protocol fees recorded
    //  [ ] referrer fees recorded
    // [ ] hooks
    //  [ ] reverts if pre-purchase hook reverts
    //  [ ] reverts if mid-purchase hook reverts
    //  [ ] reverts if post-purchase hook reverts
    //  [ ] performs pre-purchase hook
    //  [ ] performs pre-purchase hook with fees
    //  [ ] performs mid-purchase hook
    //  [ ] performs mid-purchase hook with fees
    //  [ ] performs post-purchase hook
    //  [ ] performs post-purchase hook with fees
    // [ ] non-hooks
    //  [ ] success - transfers the quote token to the auction owner
}
