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

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

abstract contract UniswapV3DirectToLiquidityTest is Test, Permit2User {
    using Callbacks for UniswapV3DirectToLiquidity;

    address internal constant _OWNER = address(0x1);
    address internal constant _PROTOCOL = address(0x2);
    address internal constant _SELLER = address(0x3);
    address internal constant _BUYER = address(0x4);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint96 internal _lotId = 1;

    AuctionHouse internal _auctionHouse;
    UniswapV3DirectToLiquidity internal _dtl;
    IUniswapV3Factory internal _uniV3Factory;
    GUniFactory internal _gUniFactory;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;

    // Inputs
    Callbacks.Permissions internal _callbackPermissions;

    function setUp() public {
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

        _uniV3Factory = new UniswapV3FactoryClone();
        _gUniFactory = new GUniFactory(address(_uniV3Factory));
    }

    // ========== MODIFIERS ========== //

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
        // vm.writeFile(
        //     "./bytecode/UniswapV3DirectToLiquidityE7.bin",
        //     vm.toString(bytecode)
        // );
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
        // vm.writeFile(
        //     "./bytecode/UniswapV3DirectToLiquidityE5.bin",
        //     vm.toString(bytecode)
        // );
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
        // vm.writeFile(
        //     "./bytecode/UniswapV3DirectToLiquidityE6.bin",
        //     vm.toString(bytecode)
        // );
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
        // vm.writeFile(
        //     "./bytecode/UniswapV3DirectToLiquidityE4.bin",
        //     vm.toString(bytecode)
        // );

        bytes32 salt;
        if (_callbackPermissions.receiveQuoteTokens && _callbackPermissions.sendBaseTokens) {
            // E7
            salt = bytes32(0xb6756239a7c6ef20e3d74acd5fef72b0b8608557c179517b559a3463a64e4d1f);
        } else if (!_callbackPermissions.receiveQuoteTokens && _callbackPermissions.sendBaseTokens)
        {
            // E5
            salt = bytes32(0x20632d36e04681f97740fff54661f5fcab8cf6d259772e4a3701251ffbc50e62);
        } else if (_callbackPermissions.receiveQuoteTokens && !_callbackPermissions.sendBaseTokens)
        {
            // E6
            salt = bytes32(0x0effe14756e174bf98869fa4948f0ab6d501864ccc9afdc227dea623baf5fd35);
        } else {
            // E4
            salt = bytes32(0xde041fd860cdaff3ae78fa4ca8a81d1f6cb3a6f2cc58ece642eafd480b7eefdd);
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
}
