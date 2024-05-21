// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Test scaffolding
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {WithSalts} from "test/lib/WithSalts.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockBPOOL} from "test/callbacks/liquidity/BaselineV2/mocks/MockBPOOL.sol";
import {IUniswapV3Factory} from "uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {UniswapV3Factory} from "test/lib/uniswap-v3/UniswapV3Factory.sol";

// Axis core
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/batch/EMP.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

// Callbacks
import {Callbacks} from "src/lib/Callbacks.sol";
import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";

abstract contract BaselineAxisLaunchTest is Test, Permit2User, WithSalts {
    using Callbacks for BaselineAxisLaunch;

    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_RESERVE = address(0xBC);
    address internal constant _NOT_SELLER = address(0x20);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint48 internal constant _START = 1_000_000;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    EncryptedMarginalPrice internal _empModule;
    FixedPriceBatch internal _fpbModule;
    BaselineAxisLaunch internal _dtl;
    address internal _dtlAddress;
    IUniswapV3Factory internal _uniV3Factory;

    IAuction internal _auctionModule;

    MockERC20 internal _quoteToken;
    MockBPOOL internal _baseToken;

    // Inputs
    BaselineAxisLaunch.CreateData internal _createData = BaselineAxisLaunch.CreateData({
        initAnchorTick: 0,
        percentReservesFloor: 0,
        anchorTickWidth: 0,
        discoveryTickWidth: 0,
        allowlistParams: abi.encode("")
    });

    function setUp() public {
        // Set reasonable timestamp
        vm.warp(_START);

        // Create an BatchAuctionHouse at a deterministic address, since it is used as input to callbacks
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

        // Create auction modules
        _empModule = new EncryptedMarginalPrice(address(_auctionHouse));
        _fpbModule = new FixedPriceBatch(address(_auctionHouse));

        // Create the quote token at a deterministic address
        bytes32 quoteTokenSalt = _getTestSalt(
            "QuoteToken", type(MockERC20).creationCode, abi.encode("Quote Token", "QT", 18)
        );
        _quoteToken = new MockERC20{salt: quoteTokenSalt}("Quote Token", "QT", 18);

        // Set base token to BPOOL
        _baseToken =
            new MockBPOOL("Base Token", "BT", 18, address(_uniV3Factory), address(_quoteToken), 500);
    }

    // ========== MODIFIERS ========== //

    modifier givenCallbackIsCreated() {
        // Callback permissions
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: true,
            onCurate: true,
            onPurchase: false,
            onBid: true,
            onSettle: true,
            receiveQuoteTokens: true,
            sendBaseTokens: true
        });

        // Get the salt
        bytes memory args =
            abi.encode(address(_auctionHouse), permissions, _BASELINE_KERNEL, address(_quoteToken));
        bytes32 salt =
            _getTestSalt("BaselineAxisLaunch", type(BaselineAxisLaunch).creationCode, args);

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new BaselineAxisLaunch{salt: salt}(
            address(_auctionHouse), permissions, _BASELINE_KERNEL, address(_quoteToken)
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

    modifier givenAuctionFormatIsEmp() {
        _auctionModule = _empModule;
        _;
    }

    modifier givenAuctionFormatIsFpb() {
        _auctionModule = _fpbModule;
        _;
    }

    function _onCreate() internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false,
            abi.encode(_createData)
        );
    }

    modifier givenOnCreate() {
        _onCreate();
        _;
    }

    // ========== MOCKS ========== //

    function _mockGetAuctionModuleForId() internal {
        vm.mockCall(
            address(_auctionHouse),
            abi.encodeWithSelector(IAuctionHouse.getAuctionModuleForId.selector, _lotId),
            abi.encode(address(_auctionModule))
        );
    }
}
