// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";

import {IUniswapV2Factory} from "src/lib/uniswap-v2/IUniswapV2Factory.sol";
import {UniswapV2FactoryClone} from "test/lib/uniswap-v2/UniswapV2FactoryClone.sol";

import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";
import {UniswapV2Router02} from "uniswap-v2-periphery/UniswapV2Router02.sol";

import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV2DirectToLiquidity} from "src/callbacks/liquidity/UniswapV2DTL.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {WithSalts} from "test/lib/WithSalts.sol";
import {console2} from "forge-std/console2.sol";

abstract contract UniswapV2DirectToLiquidityTest is Test, Permit2User, WithSalts {
    using Callbacks for UniswapV2DirectToLiquidity;

    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _NOT_SELLER = address(0x20);
    address internal constant _AUCTION_HOUSE = address(0x000000000000000000000000000000000000000A);
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint48 internal constant _START = 1_000_000;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    UniswapV2DirectToLiquidity internal _dtl;
    address internal _dtlAddress;
    IUniswapV2Factory internal _uniV2Factory;
    IUniswapV2Router02 internal _uniV2Router;
    LinearVesting internal _linearVesting;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;

    // Inputs
    BaseDirectToLiquidity.OnCreateParams internal _dtlCreateParams = BaseDirectToLiquidity
        .OnCreateParams({
        proceedsUtilisationPercent: 1e5,
        vestingStart: 0,
        vestingExpiry: 0,
        recipient: _SELLER,
        implParams: abi.encode("")
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

        // Create a UniswapV2Factory at a deterministic address
        UniswapV2FactoryClone uniV2Factory = new UniswapV2FactoryClone();
        _uniV2Factory = UniswapV2FactoryClone(_UNISWAP_V2_FACTORY);
        vm.etch(address(_uniV2Factory), address(uniV2Factory).code);
        // No storage slots to set

        // Create a UniswapV2Router at a deterministic address
        _uniV2Router = new UniswapV2Router02{
            salt: bytes32(0x035ba535d735a8e92093764ec05c30d49ab56cfd0d3da306185ab02b1fcac4f4)
        }(address(_uniV2Factory), address(0));
        console2.log("UniswapV2Router address: {}", address(_uniV2Router)); // 0x095b215677db999c3A268c16A31b15A28B2e572F

        _linearVesting = new LinearVesting(address(_auctionHouse));

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
        bytes memory args = abi.encode(
            address(_auctionHouse), _SELLER, address(_uniV2Factory), address(_uniV2Router)
        );
        bytes32 salt = _getSalt(
            "UniswapV2DirectToLiquidity", type(UniswapV2DirectToLiquidity).creationCode, args
        );

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new UniswapV2DirectToLiquidity{salt: salt}(
            address(_auctionHouse), _SELLER, address(_uniV2Factory), address(_uniV2Router)
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

    modifier givenOnCreate() {
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false,
            abi.encode(_dtlCreateParams)
        );
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
            address baseToken_,
            address quoteToken_,
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
            baseToken: baseToken_,
            quoteToken: quoteToken_,
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
