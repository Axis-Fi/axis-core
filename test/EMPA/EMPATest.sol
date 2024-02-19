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

abstract contract EMPATest is Test, Permit2User {
    MockFeeOnTransferERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockDerivativeModule internal mockDerivativeModule;
    MockAllowlist internal mockAllowlist;
    MockHook internal mockHook;

    EncryptedMarginalPriceAuction internal auctionHouse;

    address internal auctionOwner = address(0x1);
    address internal immutable protocol = address(0x2);
    address internal immutable curator = address(0x3);

    // Input to parameters
    uint48 internal startTime;
    uint48 internal duration = 1 days;
    uint24 internal constant MIN_FILL_PERCENT = 1000;
    uint24 internal constant MIN_BID_PERCENT = 100;
    uint96 internal constant LOT_CAPACITY = 10e18;
    uint96 internal constant MIN_PRICE = 2e18;
    uint256 internal auctionPrivateKey;
    Point internal auctionPublicKey;

    string internal constant INFO_HASH = "info hash";

    // Parameters
    EncryptedMarginalPriceAuction.RoutingParams internal routingParams;
    EncryptedMarginalPriceAuction.AuctionParams internal auctionParams;

    // Outputs
    uint96 internal lotId = type(uint96).max; // Set to max to ensure it's not a valid lot id

    function setUp() external {
        baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new EncryptedMarginalPriceAuction(address(this), protocol, _PERMIT2_ADDRESS);
        mockDerivativeModule = new MockDerivativeModule(address(auctionHouse));
        mockAllowlist = new MockAllowlist();
        mockHook = new MockHook(address(quoteToken), address(baseToken));

        auctionPrivateKey = 112_233_445_566;
        auctionPublicKey = ECIES.calcPubKey(Point(1, 2), bytes32(auctionPrivateKey));
        startTime = uint48(block.timestamp) + 1;

        auctionParams = EncryptedMarginalPriceAuction.AuctionParams({
            start: startTime,
            duration: duration,
            minFillPercent: MIN_FILL_PERCENT,
            minBidPercent: MIN_BID_PERCENT,
            capacity: LOT_CAPACITY,
            minimumPrice: MIN_PRICE,
            publicKey: auctionPublicKey
        });

        routingParams = EncryptedMarginalPriceAuction.RoutingParams({
            baseToken: baseToken,
            quoteToken: quoteToken,
            curator: curator,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            wrapDerivative: false,
            derivativeParams: abi.encode("")
        });
    }

    // ===== Modifiers ===== //

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", decimals_);

        // Update routing params
        routingParams.baseToken = baseToken;
    }

    modifier givenBaseTokenHasDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", decimals_);

        // Update routing params
        routingParams.quoteToken = quoteToken;
    }

    modifier givenQuoteTokenHasDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
        _;
    }

    modifier whenAllowlistIsSet() {
        // Update routing params
        routingParams.allowlist = mockAllowlist;
        _;
    }

    modifier whenHooksIsSet() {
        // Update routing params
        routingParams.hooks = mockHook;
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

    modifier givenAuctionIsCreated() {
        vm.prank(auctionOwner);
        auctionHouse.auction(routingParams, auctionParams, INFO_HASH);
        _;
    }

    modifier givenOwnerHasBaseTokenAllowance(uint256 amount_) {
        // Approve the auction house
        vm.prank(auctionOwner);
        baseToken.approve(address(auctionHouse), amount_);
        _;
    }

    modifier givenOwnerHasBaseTokenBalance(uint256 amount_) {
        // Mint the amount to the owner
        baseToken.mint(auctionOwner, amount_);
        _;
    }

    // ===== Helper Functions ===== //

    function _getLotRouting(uint96 lotId_)
        internal
        view
        returns (EncryptedMarginalPriceAuction.Routing memory)
    {
        (
            address owner_,
            ERC20 baseToken_,
            ERC20 quoteToken_,
            address curator_,
            uint96 curatorFee_,
            bool curated_,
            IHooks hooks_,
            IAllowlist allowlist_,
            Veecode derivativeRef_,
            bool wrapDerivative_,
            bytes memory derivativeParams_
        ) = auctionHouse.lotRouting(lotId_);

        return EncryptedMarginalPriceAuction.Routing({
            owner: owner_,
            baseToken: baseToken_,
            quoteToken: quoteToken_,
            curator: curator_,
            curatorFee: curatorFee_,
            curated: curated_,
            hooks: hooks_,
            allowlist: allowlist_,
            derivativeReference: derivativeRef_,
            wrapDerivative: wrapDerivative_,
            derivativeParams: derivativeParams_
        });
    }

    function _getLotData(uint96 lot_id)
        internal
        view
        returns (EncryptedMarginalPriceAuction.Lot memory)
    {
        (
            uint96 minimumPrice_,
            uint96 capacity_,
            uint8 quoteTokenDecimals_,
            uint8 baseTokenDecimals_,
            uint48 start_,
            uint48 conclusion_,
            EncryptedMarginalPriceAuction.AuctionStatus status_,
            uint96 minFilled_,
            uint96 minBidSize_
        ) = auctionHouse.lotData(lot_id);

        return EncryptedMarginalPriceAuction.Lot({
            minimumPrice: minimumPrice_,
            capacity: capacity_,
            quoteTokenDecimals: quoteTokenDecimals_,
            baseTokenDecimals: baseTokenDecimals_,
            start: start_,
            conclusion: conclusion_,
            status: status_,
            minFilled: minFilled_,
            minBidSize: minBidSize_
        });
    }
}
