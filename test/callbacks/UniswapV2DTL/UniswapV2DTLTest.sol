// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

import {IUniswapV2Factory} from "src/lib/uniswap-v2/IUniswapV2Factory.sol";
import {UniswapV2FactoryClone} from "test/lib/uniswap-v2/UniswapV2FactoryClone.sol";

import {IUniswapV2Router02} from "uniswap-v2-periphery/interfaces/IUniswapV2Router02.sol";
import {UniswapV2Router02} from "uniswap-v2-periphery/UniswapV2Router02.sol";

import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV2DirectToLiquidity} from "src/callbacks/liquidity/UniswapV2DTL.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

abstract contract UniswapV2DirectToLiquidityTest is Test, Permit2User {
    using Callbacks for UniswapV2DirectToLiquidity;

    address internal constant _OWNER = address(0x1);
    address internal constant _PROTOCOL = address(0x2);
    address internal constant _SELLER = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _NOT_SELLER = address(0x20);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint48 internal constant _START = 1_000_000;

    uint96 internal _lotId = 1;

    AuctionHouse internal _auctionHouse;
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

        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        AuctionHouse auctionHouse = new AuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = AuctionHouse(address(0x000000000000000000000000000000000000000A));
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        // // Uncomment to regenerate bytecode to mine new salts if the UniswapV2FactoryClone changes
        // // cast create2 -s 00 -i $(cat ./bytecode/UniswapV2FactoryClone.bin)
        // bytes memory bytecode = abi.encodePacked(type(UniswapV2FactoryClone).creationCode);
        // vm.writeFile("./bytecode/UniswapV2FactoryClone.bin", vm.toString(bytecode));
        _uniV2Factory = new UniswapV2FactoryClone{
            salt: bytes32(0x911053989b82d03d4ebf250c9295372f0f07d0680da49ce333cb5aa9297dde95)
        }();

        // // Uncomment to regenerate bytecode to mine new salts if the UniswapV2Router02 changes
        // // cast create2 -s 00 -i $(cat ./bytecode/UniswapV2Router02.bin)
        // bytes memory bytecode = abi.encodePacked(type(UniswapV2Router02).creationCode, abi.encode(
        //         address(_uniV2Factory), address(0)
        //     ));
        // vm.writeFile("./bytecode/UniswapV2Router02.bin", vm.toString(bytecode));
        _uniV2Router = new UniswapV2Router02{
            salt: bytes32(0x035ba535d735a8e92093764ec05c30d49ab56cfd0d3da306185ab02b1fcac4f4)
        }(address(_uniV2Factory), address(0));

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
        // // Uncomment to regenerate bytecode to mine new salts if the UniswapV2DirectToLiquidity changes
        // // 11100110 = 0xE6
        // // cast create2 -s E6 -i $(cat ./bytecode/UniswapV2DirectToLiquidityE6.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(UniswapV2DirectToLiquidity).creationCode,
        //     abi.encode(
        //         address(_auctionHouse), _SELLER, address(_uniV2Factory), address(_uniV2Router)
        //     )
        // );
        // vm.writeFile("./bytecode/UniswapV2DirectToLiquidityE6.bin", vm.toString(bytecode));

        // E6
        bytes32 salt = bytes32(0x2386572fcd4da6e4f4124bfb8f20b4577db7fd84770348ed45068561c46f4f9c);

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
            uint96 lotCapacity_,
            uint96 lotCuratorPayout_,
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
