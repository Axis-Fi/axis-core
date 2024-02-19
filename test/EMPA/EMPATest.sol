// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Point, ECIES} from "src/lib/ECIES.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockEMPAHook} from "test/EMPA/mocks/MockEMPAHook.sol";

// Auctions
import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {EncryptedMarginalPriceAuction, FeeManager} from "src/EMPA.sol";

// Modules
import {toKeycode, Veecode} from "src/modules/Modules.sol";

abstract contract EmpaTest is Test, Permit2User {
    MockFeeOnTransferERC20 internal _baseToken;
    MockERC20 internal _quoteToken;
    MockDerivativeModule internal _mockDerivativeModule;
    MockAllowlist internal _mockAllowlist;
    MockEMPAHook internal _mockHook;

    EncryptedMarginalPriceAuction internal _auctionHouse;

    address internal _auctionOwner = address(0x1);
    address internal immutable _PROTOCOL = address(0x2);
    address internal immutable _CURATOR = address(0x3);

    uint24 internal constant _CURATOR_MAX_FEE = 100;
    uint24 internal constant _CURATOR_FEE = 90;

    // Input to parameters
    uint48 internal _startTime;
    uint48 internal _duration = 1 days;
    uint24 internal constant _MIN_FILL_PERCENT = 1000;
    uint24 internal constant _MIN_BID_PERCENT = 100;
    uint96 internal constant _LOT_CAPACITY = 10e18;
    uint96 internal constant _MIN_PRICE = 2e18;
    uint256 internal _auctionPrivateKey;
    Point internal _auctionPublicKey;
    string internal constant _INFO_HASH = "info hash";

    // Parameters
    EncryptedMarginalPriceAuction.RoutingParams internal _routingParams;
    EncryptedMarginalPriceAuction.AuctionParams internal _auctionParams;

    // Outputs
    uint96 internal _lotId = type(uint96).max; // Set to max to ensure it's not a valid lot id

    function setUp() external {
        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", 18);
        _quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        _auctionHouse =
            new EncryptedMarginalPriceAuction(address(this), _PROTOCOL, _PERMIT2_ADDRESS);
        _mockDerivativeModule = new MockDerivativeModule(address(_auctionHouse));
        _mockAllowlist = new MockAllowlist();
        _mockHook = new MockEMPAHook(address(_quoteToken), address(_baseToken));

        _auctionPrivateKey = 112_233_445_566;
        _auctionPublicKey = ECIES.calcPubKey(Point(1, 2), bytes32(_auctionPrivateKey));
        _startTime = uint48(block.timestamp) + 1;

        _auctionParams = EncryptedMarginalPriceAuction.AuctionParams({
            start: _startTime,
            duration: _duration,
            minFillPercent: _MIN_FILL_PERCENT,
            minBidPercent: _MIN_BID_PERCENT,
            capacity: _LOT_CAPACITY,
            minimumPrice: _MIN_PRICE,
            publicKey: _auctionPublicKey
        });

        _routingParams = EncryptedMarginalPriceAuction.RoutingParams({
            baseToken: _baseToken,
            quoteToken: _quoteToken,
            curator: _CURATOR,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            wrapDerivative: false,
            derivativeParams: abi.encode("")
        });

        // Set the max curator fee
        _auctionHouse.setFee(FeeManager.FeeType.MaxCurator, _CURATOR_MAX_FEE);
    }

    // ===== Modifiers ===== //

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", decimals_);

        // Update routing params
        _routingParams.baseToken = _baseToken;
    }

    modifier givenBaseTokenHasDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", decimals_);

        // Update routing params
        _routingParams.quoteToken = _quoteToken;
    }

    modifier givenQuoteTokenHasDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
        _;
    }

    modifier whenAllowlistIsSet() {
        // Update routing params
        _routingParams.allowlist = _mockAllowlist;
        _;
    }

    modifier whenHooksIsSet() {
        // Update routing params
        _routingParams.hooks = _mockHook;
        _;
    }

    modifier givenHookHasBaseTokenBalance(uint256 amount_) {
        // Mint the amount to the hook
        _baseToken.mint(address(_mockHook), amount_);
        _;
    }

    modifier whenDerivativeModuleIsInstalled() {
        _auctionHouse.installModule(_mockDerivativeModule);
        _;
    }

    modifier whenDerivativeTypeIsSet() {
        _routingParams.derivativeType = toKeycode("DERV");
        _;
    }

    modifier givenLotIsCreated() {
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
        _;
    }

    modifier givenOwnerHasBaseTokenAllowance(uint256 amount_) {
        // Approve the auction house
        vm.prank(_auctionOwner);
        _baseToken.approve(address(_auctionHouse), amount_);
        _;
    }

    modifier givenOwnerHasBaseTokenBalance(uint256 amount_) {
        // Mint the amount to the owner
        _baseToken.mint(_auctionOwner, amount_);
        _;
    }

    modifier givenCuratorIsSet() {
        _routingParams.curator = _CURATOR;
        _;
    }

    modifier givenCuratorHasApproved() {
        // Set the curator fee
        vm.prank(_CURATOR);
        _auctionHouse.setCuratorFee(_CURATOR_FEE);

        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
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
        ) = _auctionHouse.lotRouting(lotId_);

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

    function _getLotData(uint96 lotId_)
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
        ) = _auctionHouse.lotData(lotId_);

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
