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
import {ComputeAddress} from "test/lib/ComputeAddress.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// Axis core
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/batch/EMP.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

// Callbacks
import {Callbacks} from "src/lib/Callbacks.sol";
import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";

// Baseline
import {
    Kernel,
    toKeycode as toBaselineKeycode
} from "src/callbacks/liquidity/BaselineV2/lib/Kernel.sol";

abstract contract BaselineAxisLaunchTest is Test, Permit2User, WithSalts {
    using Callbacks for BaselineAxisLaunch;

    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _NOT_SELLER = address(0x20);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xe9d3A46B2a5813eAED0ab1E2B955c29038545FbD);

    uint96 internal constant _LOT_CAPACITY = 10e18;
    uint96 internal constant _REFUND_AMOUNT = 2e18;
    uint256 internal constant _PROCEEDS_AMOUNT = 24e18;
    int24 internal constant _DISCOVERY_TICK_WIDTH = 500;
    uint256 internal constant _FIXED_PRICE = 3e18;
    uint24 internal constant _FEE_TIER = 3000;
    uint256 internal constant _BASE_SCALE = 1e18;
    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;

    uint48 internal constant _START = 1_000_000;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    EncryptedMarginalPrice internal _empModule;
    FixedPriceBatch internal _fpbModule;
    BaselineAxisLaunch internal _dtl;
    address internal _dtlAddress;
    IUniswapV3Factory internal _uniV3Factory;

    int24 internal _tickSpacing;

    IAuction internal _auctionModule;

    MockERC20 internal _quoteToken;
    MockBPOOL internal _baseToken;

    // Inputs
    IFixedPriceBatch.AuctionDataParams internal _fpbParams = IFixedPriceBatch.AuctionDataParams({
        price: _FIXED_PRICE,
        minFillPercent: 5e4 // 50%
    });

    BaselineAxisLaunch.CreateData internal _createData = BaselineAxisLaunch.CreateData({
        discoveryTickWidth: _DISCOVERY_TICK_WIDTH,
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
        vm.stopBroadcast();
        if (address(_uniV3Factory) != address(0x43de928116768b88F8BF8f768b3de90A0Aaf9551)) {
            console2.log("UniswapV3Factory address: ", address(_uniV3Factory));
            revert("UniswapV3Factory address mismatch");
        }

        // Create auction modules
        _empModule = new EncryptedMarginalPrice(address(_auctionHouse));
        _fpbModule = new FixedPriceBatch(address(_auctionHouse));

        // Default auction module is FPB
        _auctionModule = _fpbModule;
        _mockGetAuctionModuleForId();

        // Create the quote token at a deterministic address
        bytes32 quoteTokenSalt = _getTestSalt(
            "QuoteToken", type(MockERC20).creationCode, abi.encode("Quote Token", "QT", 18)
        );
        _quoteToken = new MockERC20{salt: quoteTokenSalt}("Quote Token", "QT", 18);
        _quoteTokenDecimals = 18;
        if (address(_quoteToken) != _BASELINE_QUOTE_TOKEN) {
            console2.log("Quote Token address: ", address(_quoteToken));
            revert("Quote Token address mismatch");
        }

        // Generate a salt so that the base token address is higher than the quote token
        bytes32 baseTokenSalt = ComputeAddress.generateSalt(
            _BASELINE_QUOTE_TOKEN,
            true,
            type(MockBPOOL).creationCode,
            abi.encode(
                "Base Token", "BT", 18, address(_uniV3Factory), _BASELINE_QUOTE_TOKEN, _FEE_TIER
            ),
            address(this)
        );

        // Set base token to BPOOL
        _baseToken = new MockBPOOL{salt: baseTokenSalt}(
            "Base Token", "BT", 18, address(_uniV3Factory), _BASELINE_QUOTE_TOKEN, 3000
        );
        _baseTokenDecimals = 18;
        _tickSpacing = _uniV3Factory.feeAmountTickSpacing(_FEE_TIER);
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
            abi.encode(address(_auctionHouse), permissions, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN);
        bytes32 salt =
            _getTestSalt("BaselineAxisLaunch", type(BaselineAxisLaunch).creationCode, args);

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new BaselineAxisLaunch{salt: salt}(
            address(_auctionHouse), permissions, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN
        );
        vm.stopBroadcast();

        _dtlAddress = address(_dtl);

        // Call configureDependencies to set everything that's needed
        _mockBaselineGetModuleForKeycode();
        _dtl.configureDependencies();
        _;
    }

    modifier givenAuctionFormatIsEmp() {
        _auctionModule = _empModule;
        _mockGetAuctionModuleForId();
        _;
    }

    modifier givenAuctionIsCreated() {
        // Create a dummy auction in the module
        IAuction.AuctionParams memory auctionParams = IAuction.AuctionParams({
            start: _START,
            duration: 1 days,
            capacityInQuote: false,
            capacity: _scaleBaseTokenAmount(_LOT_CAPACITY),
            implParams: abi.encode(_fpbParams)
        });

        vm.prank(address(_auctionHouse));
        _fpbModule.auction(_lotId, auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
        _;
    }

    function _onCreate() internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            true,
            abi.encode(_createData)
        );
    }

    modifier givenOnCreate() {
        _onCreate();
        _;
    }

    function onCancel() internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCancel(_lotId, _scaleBaseTokenAmount(_REFUND_AMOUNT), true, abi.encode(""));
    }

    modifier givenOnCancel() {
        onCancel();
        _;
    }

    function onSettle() internal {
        vm.prank(address(_auctionHouse));
        _dtl.onSettle(
            _lotId, _PROCEEDS_AMOUNT, _scaleBaseTokenAmount(_REFUND_AMOUNT), abi.encode("")
        );
    }

    modifier givenOnSettle() {
        onSettle();
        _;
    }

    modifier givenBPoolFeeTier(uint24 feeTier_) {
        // Generate a salt so that the base token address is higher than the quote token
        bytes32 baseTokenSalt = ComputeAddress.generateSalt(
            _BASELINE_QUOTE_TOKEN,
            true,
            type(MockBPOOL).creationCode,
            abi.encode(
                "Base Token", "BT", 18, address(_uniV3Factory), _BASELINE_QUOTE_TOKEN, feeTier_
            ),
            address(this)
        );

        // Create a new mock BPOOL with the given fee tier
        _baseToken = new MockBPOOL(
            "Base Token", "BT", 18, address(_uniV3Factory), _BASELINE_QUOTE_TOKEN, feeTier_
        );
        _tickSpacing = _uniV3Factory.feeAmountTickSpacing(feeTier_);
        _;
    }

    modifier givenBaseTokenAddressLower() {
        // Generate a salt so that the base token address is lower than the quote token
        bytes32 baseTokenSalt = ComputeAddress.generateSalt(
            _BASELINE_QUOTE_TOKEN,
            false,
            type(MockBPOOL).creationCode,
            abi.encode(
                "Base Token", "BT", 18, address(_uniV3Factory), _BASELINE_QUOTE_TOKEN, _FEE_TIER
            ),
            address(this)
        );

        // Create a new mock BPOOL with the given address
        _baseToken = new MockBPOOL{salt: baseTokenSalt}(
            "Base Token", "BT", 18, address(_uniV3Factory), _BASELINE_QUOTE_TOKEN, _FEE_TIER
        );
        _tickSpacing = _uniV3Factory.feeAmountTickSpacing(_FEE_TIER);
        _;
    }

    modifier givenBaseTokenDecimals(uint8 decimals_) {
        // Create a new mock BPOOL with the given decimals
        _baseToken = new MockBPOOL(
            "Base Token", "BT", decimals_, address(_uniV3Factory), _BASELINE_QUOTE_TOKEN, _FEE_TIER
        );
        _baseTokenDecimals = decimals_;
        _tickSpacing = _uniV3Factory.feeAmountTickSpacing(_FEE_TIER);
        _;
    }

    modifier givenFixedPrice(uint256 fixedPrice_) {
        _fpbParams.price = fixedPrice_;
        _;
    }

    modifier givenDiscoveryTickWidth(int24 discoveryTickWidth_) {
        _createData.discoveryTickWidth = discoveryTickWidth_;
        _;
    }

    function _scaleBaseTokenAmount(uint256 amount_) internal view returns (uint256) {
        return FixedPointMathLib.mulDivDown(amount_, 10 ** _baseTokenDecimals, _BASE_SCALE);
    }

    // ========== MOCKS ========== //

    function _mockGetAuctionModuleForId() internal {
        vm.mockCall(
            address(_auctionHouse),
            abi.encodeWithSelector(IAuctionHouse.getAuctionModuleForId.selector, _lotId),
            abi.encode(address(_auctionModule))
        );
    }

    function _mockBaselineGetModuleForKeycode() internal {
        vm.mockCall(
            _BASELINE_KERNEL,
            abi.encodeWithSelector(
                bytes4(keccak256("getModuleForKeycode(bytes5)")), toBaselineKeycode("BPOOL")
            ),
            abi.encode(address(_baseToken))
        );
    }
}
