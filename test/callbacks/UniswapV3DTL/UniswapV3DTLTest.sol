// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

import {GUniFactory} from "g-uni-v1-core/GUniFactory.sol";
import {GUniPool} from "g-uni-v1-core/GUniPool.sol";
import {IUniswapV3Factory} from "uniswap-v3-core/interfaces/IUniswapV3Factory.sol";

import {UniswapV3Factory} from "test/lib/uniswap-v3/UniswapV3Factory.sol";

import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

abstract contract UniswapV3DirectToLiquidityTest is Test, Permit2User {
    using Callbacks for UniswapV3DirectToLiquidity;

    address internal constant _OWNER = address(0x1);
    address internal constant _PROTOCOL = address(0x2);
    address internal constant _SELLER = address(0x3);
    address internal constant _BUYER = address(0x4);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint48 internal constant _START = 1_000_000;

    uint96 internal _lotId = 1;

    AuctionHouse internal _auctionHouse;
    UniswapV3DirectToLiquidity internal _dtl;
    address internal _dtlAddress;
    IUniswapV3Factory internal _uniV3Factory;
    GUniFactory internal _gUniFactory;
    LinearVesting internal _linearVesting;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;

    // Inputs
    Callbacks.Permissions internal _callbackPermissions;
    UniswapV3DirectToLiquidity.DTLParams internal _dtlCreateParams = UniswapV3DirectToLiquidity
        .DTLParams({proceedsUtilisationPercent: 1e5, poolFee: 500, vestingStart: 0, vestingExpiry: 0});

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

        // Set default permissions
        _callbackPermissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: true,
            onCurate: true,
            onPurchase: false,
            onBid: false,
            onClaimProceeds: true,
            receiveQuoteTokens: true,
            sendBaseTokens: false
        });

        // // Uncomment to regenerate bytecode to mine new salts if the UniswapV3Factory changes
        // // cast create2 -s 00 -i $(cat ./bytecode/UniswapV3Factory.bin)
        // bytes memory bytecode = abi.encodePacked(type(UniswapV3Factory).creationCode);
        // vm.writeFile("./bytecode/UniswapV3Factory.bin", vm.toString(bytecode));
        _uniV3Factory = new UniswapV3Factory{
            salt: bytes32(0xbc65534283bdbbac4a95a3fb1933af63d55135566688dd54d1c55a626b1bc366)
        }();

        // // Uncomment to regenerate bytecode to mine new salts if the GUniFactory changes
        // // cast create2 -s 00 -i $(cat ./bytecode/GUniFactory.bin)
        // bytes memory bytecode =
        //     abi.encodePacked(type(GUniFactory).creationCode, abi.encode(address(_uniV3Factory)));
        // vm.writeFile("./bytecode/GUniFactory.bin", vm.toString(bytecode));
        _gUniFactory = new GUniFactory{
            salt: bytes32(0x31d4bb3a2cd73df799deceac86fa252d040e24c2ea206f4172d74f72cfa34e4b)
        }(address(_uniV3Factory));

        // Initialize the GUniFactory
        address payable gelatoAddress = payable(address(0x10));
        GUniPool poolImplementation = new GUniPool(gelatoAddress);
        _gUniFactory.initialize(address(poolImplementation), address(0), address(this));

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

    modifier givenCallbackSendBaseTokensIsSet() {
        _callbackPermissions.sendBaseTokens = true;
        _;
    }

    modifier givenCallbackIsCreated() {
        // // Uncomment to regenerate bytecode to mine new salts if the UniswapV3DirectToLiquidity changes
        // // 11100111 = 0xE7
        // // cast create2 -s E7 -i $(cat ./bytecode/UniswapV3DirectToLiquidityE7.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(UniswapV3DirectToLiquidity).creationCode,
        //     abi.encode(
        //         address(_auctionHouse),
        //         Callbacks.Permissions({
        //             onCreate: true,
        //             onCancel: true,
        //             onCurate: true,
        //             onPurchase: false,
        //             onBid: false,
        //             onClaimProceeds: true,
        //             receiveQuoteTokens: true,
        //             sendBaseTokens: true
        //         }),
        //         _SELLER,
        //         address(_uniV3Factory),
        //         address(_gUniFactory)
        //     )
        // );
        // vm.writeFile("./bytecode/UniswapV3DirectToLiquidityE7.bin", vm.toString(bytecode));
        // // 11100110 = 0xE6
        // // cast create2 -s E6 -i $(cat ./bytecode/UniswapV3DirectToLiquidityE6.bin)
        // bytecode = abi.encodePacked(
        //     type(UniswapV3DirectToLiquidity).creationCode,
        //     abi.encode(
        //         address(_auctionHouse),
        //         Callbacks.Permissions({
        //             onCreate: true,
        //             onCancel: true,
        //             onCurate: true,
        //             onPurchase: false,
        //             onBid: false,
        //             onClaimProceeds: true,
        //             receiveQuoteTokens: true,
        //             sendBaseTokens: false
        //         }),
        //         _SELLER,
        //         address(_uniV3Factory),
        //         address(_gUniFactory)
        //     )
        // );
        // vm.writeFile("./bytecode/UniswapV3DirectToLiquidityE6.bin", vm.toString(bytecode));

        bytes32 salt;
        if (_callbackPermissions.receiveQuoteTokens && _callbackPermissions.sendBaseTokens) {
            // E7
            salt = bytes32(0x119b11dc7ff84f8e9e0dc6bedadac973c450fab0b2e12101aedeb67fd19f0aa4);
        } else {
            // E6
            salt = bytes32(0x0748f46d1ccf5be29c02dc9833b69a1f72540466b76d110551b4cf1fbf559bbd);
        }

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new UniswapV3DirectToLiquidity{salt: salt}(
            address(_auctionHouse),
            _callbackPermissions,
            _SELLER,
            address(_uniV3Factory),
            address(_gUniFactory)
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
        bool isPrefund = _callbackPermissions.sendBaseTokens;

        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, curatorPayout_, isPrefund, abi.encode(""));
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
        _dtlCreateParams.poolFee = fee_;
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

    // ========== FUNCTIONS ========== //

    function _getDTLConfiguration(uint96 lotId_)
        internal
        view
        returns (UniswapV3DirectToLiquidity.DTLConfiguration memory)
    {
        (
            address baseToken_,
            address quoteToken_,
            uint96 lotCapacity_,
            uint96 lotCuratorPayout_,
            uint24 proceedsUtilisationPercent_,
            uint24 poolFee_,
            uint48 vestingStart_,
            uint48 vestingExpiry_,
            LinearVesting linearVestingModule_,
            bool active_
        ) = _dtl.lotConfiguration(lotId_);

        return UniswapV3DirectToLiquidity.DTLConfiguration({
            baseToken: baseToken_,
            quoteToken: quoteToken_,
            lotCapacity: lotCapacity_,
            lotCuratorPayout: lotCuratorPayout_,
            proceedsUtilisationPercent: proceedsUtilisationPercent_,
            poolFee: poolFee_,
            vestingStart: vestingStart_,
            vestingExpiry: vestingExpiry_,
            linearVestingModule: linearVestingModule_,
            active: active_
        });
    }
}
