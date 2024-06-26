// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";

import {GUniFactory} from "g-uni-v1-core/GUniFactory.sol";
import {GUniPool} from "g-uni-v1-core/GUniPool.sol";
import {IUniswapV3Factory} from "uniswap-v3-core/interfaces/IUniswapV3Factory.sol";

import {UniswapV3Factory} from "test/lib/uniswap-v3/UniswapV3Factory.sol";

import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";
import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";

import {keycodeFromVeecode, toKeycode} from "src/modules/Keycode.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {WithSalts} from "test/lib/WithSalts.sol";
import {console2} from "forge-std/console2.sol";

abstract contract UniswapV3DirectToLiquidityTest is Test, Permit2User, WithSalts {
    using Callbacks for UniswapV3DirectToLiquidity;

    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _NOT_SELLER = address(0x20);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint48 internal constant _START = 1_000_000;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    UniswapV3DirectToLiquidity internal _dtl;
    address internal _dtlAddress;
    IUniswapV3Factory internal _uniV3Factory;
    GUniFactory internal _gUniFactory;
    LinearVesting internal _linearVesting;
    MockBatchAuctionModule internal _batchAuctionModule;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;

    // Inputs
    uint24 internal _poolFee = 500;
    BaseDirectToLiquidity.OnCreateParams internal _dtlCreateParams = BaseDirectToLiquidity
        .OnCreateParams({
        proceedsUtilisationPercent: 1e5,
        vestingStart: 0,
        vestingExpiry: 0,
        recipient: _SELLER,
        implParams: abi.encode(_poolFee)
    });

    function setUp() public {
        // Set reasonable timestamp
        vm.warp(_START);

        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        BatchAuctionHouse auctionHouse = new BatchAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = BatchAuctionHouse(_AUCTION_HOUSE);
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        // Create a UniswapV3Factory at a deterministic address
        vm.startBroadcast();
        _uniV3Factory = new UniswapV3Factory{
            salt: bytes32(0xbc65534283bdbbac4a95a3fb1933af63d55135566688dd54d1c55a626b1bc366)
        }();
        console2.log("UniswapV3Factory address: ", address(_uniV3Factory)); // 0x43de928116768b88F8BF8f768b3de90A0Aaf9551

        // Create a GUniFactory at a deterministic address
        _gUniFactory = new GUniFactory{
            salt: bytes32(0x31d4bb3a2cd73df799deceac86fa252d040e24c2ea206f4172d74f72cfa34e4b)
        }(address(_uniV3Factory));
        console2.log("GUniFactory address: ", address(_gUniFactory)); // 0xc46b184e5521Cb87Fc5288Ff49D978A4BE4B055c
        vm.stopBroadcast();

        // Initialize the GUniFactory
        address payable gelatoAddress = payable(address(0x10));
        GUniPool poolImplementation = new GUniPool(gelatoAddress);
        _gUniFactory.initialize(address(poolImplementation), address(0), address(this));

        _linearVesting = new LinearVesting(address(_auctionHouse));
        _batchAuctionModule = new MockBatchAuctionModule(address(_auctionHouse));

        // Install a mock batch auction module
        vm.prank(_OWNER);
        _auctionHouse.installModule(_batchAuctionModule);

        _quoteToken = new MockERC20("Quote Token", "QT", 18);
        _baseToken = new MockERC20("Base Token", "BT", 18);
    }

    // ========== MODIFIERS ========== //

    modifier givenLinearVestingModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_linearVesting);
        _;
    }

    modifier givenCallbackIsCreated() {
        // Get the salt
        bytes memory args =
            abi.encode(address(_auctionHouse), address(_uniV3Factory), address(_gUniFactory));
        bytes32 salt = _getTestSalt(
            "UniswapV3DirectToLiquidity", type(UniswapV3DirectToLiquidity).creationCode, args
        );

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new UniswapV3DirectToLiquidity{salt: salt}(
            address(_auctionHouse), address(_uniV3Factory), address(_gUniFactory)
        );
        vm.stopBroadcast();

        _dtlAddress = address(_dtl);
        _;
    }

    modifier givenAddressHasQuoteTokenBalance(address address_, uint256 amount_) {
        _quoteToken.mint(address_, amount_);
        _;
    }

    modifier givenAddressHasBaseTokenBalance(address address_, uint256 amount_) {
        _baseToken.mint(address_, amount_);
        _;
    }

    modifier givenAddressHasQuoteTokenAllowance(address owner_, address spender_, uint256 amount_) {
        vm.prank(owner_);
        _quoteToken.approve(spender_, amount_);
        _;
    }

    modifier givenAddressHasBaseTokenAllowance(address owner_, address spender_, uint256 amount_) {
        vm.prank(owner_);
        _baseToken.approve(spender_, amount_);
        _;
    }

    function _createLot(address seller_) internal returns (uint96 lotId) {
        // Mint and approve the capacity to the owner
        _baseToken.mint(seller_, _LOT_CAPACITY);
        vm.prank(seller_);
        _baseToken.approve(address(_auctionHouse), _LOT_CAPACITY);

        // Prep the lot arguments
        IAuctionHouse.RoutingParams memory routingParams = IAuctionHouse.RoutingParams({
            auctionType: keycodeFromVeecode(_batchAuctionModule.VEECODE()),
            baseToken: address(_baseToken),
            quoteToken: address(_quoteToken),
            curator: address(0),
            callbacks: _dtl,
            callbackData: abi.encode(_dtlCreateParams),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            wrapDerivative: false
        });

        IAuction.AuctionParams memory auctionParams = IAuction.AuctionParams({
            start: uint48(block.timestamp) + 1,
            duration: 1 days,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode("")
        });

        // Create a new lot
        vm.prank(seller_);
        return _auctionHouse.auction(routingParams, auctionParams, "");
    }

    modifier givenOnCreate() {
        _lotId = _createLot(_SELLER);
        _;
    }

    function _performOnCurate(uint96 curatorPayout_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, curatorPayout_, false, abi.encode(""));
    }

    modifier givenOnCurate(uint96 curatorPayout_) {
        _performOnCurate(curatorPayout_);
        _;
    }

    modifier givenProceedsUtilisationPercent(uint24 percent_) {
        _dtlCreateParams.proceedsUtilisationPercent = percent_;
        _;
    }

    modifier givenPoolFee(uint24 fee_) {
        _poolFee = fee_;
        _dtlCreateParams.implParams = abi.encode(_poolFee);
        _;
    }

    modifier givenVestingStart(uint48 start_) {
        _dtlCreateParams.vestingStart = start_;
        _;
    }

    modifier givenVestingExpiry(uint48 end_) {
        _dtlCreateParams.vestingExpiry = end_;
        _;
    }

    modifier whenRecipientIsNotSeller() {
        _dtlCreateParams.recipient = _NOT_SELLER;
        _;
    }

    // ========== FUNCTIONS ========== //

    function _getDTLConfiguration(uint96 lotId_)
        internal
        view
        returns (BaseDirectToLiquidity.DTLConfiguration memory)
    {
        (
            address recipient_,
            uint256 lotCapacity_,
            uint256 lotCuratorPayout_,
            uint24 proceedsUtilisationPercent_,
            uint48 vestingStart_,
            uint48 vestingExpiry_,
            LinearVesting linearVestingModule_,
            bool active_,
            bytes memory implParams_
        ) = _dtl.lotConfiguration(lotId_);

        return BaseDirectToLiquidity.DTLConfiguration({
            recipient: recipient_,
            lotCapacity: lotCapacity_,
            lotCuratorPayout: lotCuratorPayout_,
            proceedsUtilisationPercent: proceedsUtilisationPercent_,
            vestingStart: vestingStart_,
            vestingExpiry: vestingExpiry_,
            linearVestingModule: linearVestingModule_,
            active: active_,
            implParams: implParams_
        });
    }
}
