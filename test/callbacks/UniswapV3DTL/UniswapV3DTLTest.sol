// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

import {GUniFactory} from "g-uni-v1-core/GUniFactory.sol";
import {IUniswapV3Factory} from "uniswap-v3-core/interfaces/IUniswapV3Factory.sol";

import {UniswapV3FactoryClone} from "test/lib/uniswap-v3/UniswapV3FactoryClone.sol";

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
    IUniswapV3Factory internal _uniV3Factory;
    GUniFactory internal _gUniFactory;
    LinearVesting internal _linearVesting;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;

    // Inputs
    Callbacks.Permissions internal _callbackPermissions;

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
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // // Uncomment to regenerate bytecode to mine new salts if the UniswapV3FactoryClone changes
        // // cast create2 -s 00 -i $(cat ./bytecode/UniswapV3FactoryClone.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(UniswapV3FactoryClone).creationCode
        // );
        // vm.writeFile(
        //     "./bytecode/UniswapV3FactoryClone.bin",
        //     vm.toString(bytecode)
        // );
        _uniV3Factory = new UniswapV3FactoryClone{
            salt: bytes32(0xbecf6f3548fab5820a733e3b397c3bf2cf4c0a7e7df3060a45ae5a5037ac241e)
        }();

        // Set the storage slots
        vm.store(address(_uniV3Factory), bytes32(uint256(3)), bytes32(abi.encode(_OWNER))); // Owner

        // Set the standard fees
        vm.startPrank(_OWNER);
        _uniV3Factory.enableFeeAmount(500, 10);
        _uniV3Factory.enableFeeAmount(3000, 60);
        _uniV3Factory.enableFeeAmount(10_000, 200);
        vm.stopPrank();

        // // Uncomment to regenerate bytecode to mine new salts if the GUniFactory changes
        // // cast create2 -s 00 -i $(cat ./bytecode/GUniFactory.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(GUniFactory).creationCode,
        //     abi.encode(address(_uniV3Factory))
        // );
        // vm.writeFile(
        //     "./bytecode/GUniFactory.bin",
        //     vm.toString(bytecode)
        // );
        _gUniFactory = new GUniFactory{
            salt: bytes32(0xfdb23b8a5d4bf11c4f82da11e01689a4cfbda09325a6f57a3146afd4f5f12de1)
        }(address(_uniV3Factory));
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

    modifier givenCallbackReceiveQuoteTokensIsSet() {
        _callbackPermissions.receiveQuoteTokens = true;
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
        // // 11100101 = 0xE5
        // // cast create2 -s E5 -i $(cat ./bytecode/UniswapV3DirectToLiquidityE5.bin)
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
        //             receiveQuoteTokens: false,
        //             sendBaseTokens: true
        //         }),
        //         _SELLER,
        //         address(_uniV3Factory),
        //         address(_gUniFactory)
        //     )
        // );
        // vm.writeFile("./bytecode/UniswapV3DirectToLiquidityE5.bin", vm.toString(bytecode));
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
        // // 11100100 = 0xE4
        // // cast create2 -s E4 -i $(cat ./bytecode/UniswapV3DirectToLiquidityE4.bin)
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
        //             receiveQuoteTokens: false,
        //             sendBaseTokens: false
        //         }),
        //         _SELLER,
        //         address(_uniV3Factory),
        //         address(_gUniFactory)
        //     )
        // );
        // vm.writeFile("./bytecode/UniswapV3DirectToLiquidityE4.bin", vm.toString(bytecode));

        bytes32 salt;
        if (_callbackPermissions.receiveQuoteTokens && _callbackPermissions.sendBaseTokens) {
            // E7
            salt = bytes32(0xbbd0d7c7133883d8e735b48012a39b258f4338e9eadb87565b6ac38d575c226b);
        } else if (!_callbackPermissions.receiveQuoteTokens && _callbackPermissions.sendBaseTokens)
        {
            // E5
            salt = bytes32(0xc71aa076906182068c4ce2fa8d29085575e322c8fac556a26a42e1d95bea9890);
        } else if (_callbackPermissions.receiveQuoteTokens && !_callbackPermissions.sendBaseTokens)
        {
            // E6
            salt = bytes32(0x30e50df555014d6b7c7f2012a077c818432c8c11001d6e5f39b63ce39e1a8419);
        } else {
            // E4
            salt = bytes32(0x85408c4c2e11266cb4cd15465b54b1d1df605f0011071423b644a79128c604c4);
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
