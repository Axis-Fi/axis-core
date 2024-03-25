// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

import {UniswapV3DirectToLiquidity} from "src/callbacks/liquidity/UniswapV3DTL.sol";
import {BaseCallback} from "src/callbacks/BaseCallback.sol";

contract UniswapV3DirectToLiquidityOnCreateTest is UniswapV3DirectToLiquidityTest {
    // Function inputs
    UniswapV3DirectToLiquidity.DTLParams internal _dtlParams = UniswapV3DirectToLiquidity.DTLParams({
        proceedsUtilisationPercent: 1e5,
        poolFee: 500,
        vestingStart: 0,
        vestingExpiry: 0
    });

    // ============ Modifiers ============ //

    function _performCallback() internal {
        bool isPrefund = _callbackPermissions.sendBaseTokens;

        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            isPrefund,
            abi.encode(_dtlParams)
        );
    }

    modifier givenProceedsUtilisationPercent(uint24 percent_) {
        _dtlParams.proceedsUtilisationPercent = percent_;
        _;
    }

    modifier givenPoolFee(uint24 fee_) {
        _dtlParams.poolFee = fee_;
        _;
    }

    modifier givenVestingStart(uint48 start_) {
        _dtlParams.vestingStart = start_;
        _;
    }

    modifier givenVestingExpiry(uint48 end_) {
        _dtlParams.vestingExpiry = end_;
        _;
    }

    // ============ Assertions ============ //

    function _expectTransferFrom() internal {
        vm.expectRevert("TRANSFER_FROM");
    }

    function _expectInvalidParams() internal {
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);
    }

    function _expectNotAuthorized() internal {
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);
    }

    function _assertBaseTokenBalances() internal {
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller balance");
        assertEq(_baseToken.balanceOf(address(_dtl)), 0, "dtl balance");

        // If the send base tokens flag is enabled, the base tokens should be transferred to the auction house
        if (_callbackPermissions.sendBaseTokens) {
            assertEq(
                _baseToken.balanceOf(address(_auctionHouse)), _LOT_CAPACITY, "auction house balance"
            );
        }
    }

    // ============ Tests ============ //

    // [X] when the callback data is incorrect
    //  [X] it reverts
    // [X] when the callback is not called by the auction house
    //  [X] it reverts
    // [X] when the lot has already been registered
    //  [X] it reverts
    // [X] when the proceeds utilisation is 0
    //  [X] it reverts
    // [X] when the proceeds utilisation is greater than 100%
    //  [X] it reverts
    // [X] given the pool fee is not enabled
    //  [X] it reverts
    // [X] given uniswap v3 pool already exists
    //  [X] it reverts
    // [X] when the start and expiry timestamps are the same
    //  [X] it reverts
    // [X] when the start timestamp is after the expiry timestamp
    //  [X] it reverts
    // [X] when the start timestamp is before the current timestamp
    //  [X] it succeeds
    // [X] when the expiry timestamp is before the current timestamp
    //  [X] it reverts
    // [X] when the start timestamp and expiry timestamp are specified
    //  [X] given the linear vesting module is not installed
    //   [X] it reverts
    //  [X] it records the address of the linear vesting module
    // [X] given the send base tokens flag is enabled
    //  [X] given the seller has an insufficient balance
    //   [X] it reverts
    //  [X] given the seller has an insufficient allowance
    //   [X] it reverts
    //  [X] it registers the lot, transfers the base tokens to the auction house
    // [X] it registers the lot

    function test_whenCallbackDataIsIncorrect_reverts() public givenCallbackIsCreated {
        _expectInvalidParams();

        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false,
            abi.encode(uint256(10))
        );
    }

    function test_whenCallbackIsNotCalledByAuctionHouse_reverts() public givenCallbackIsCreated {
        _expectNotAuthorized();

        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false,
            abi.encode(_dtlParams)
        );
    }

    function test_whenLotHasAlreadyBeenRegistered_reverts() public givenCallbackIsCreated {
        _performCallback();

        _expectInvalidParams();

        _performCallback();
    }

    function test_whenProceedsUtilisationIs0_reverts()
        public
        givenCallbackIsCreated
        givenProceedsUtilisationPercent(0)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DirectToLiquidity.Callback_Params_UtilisationPercentOutOfBounds.selector,
            0,
            1,
            1e5
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenProceedsUtilisationIsGreaterThan100Percent_reverts()
        public
        givenCallbackIsCreated
        givenProceedsUtilisationPercent(1e5 + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DirectToLiquidity.Callback_Params_UtilisationPercentOutOfBounds.selector,
            1e5 + 1,
            1,
            1e5
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_givenPoolFeeIsNotEnabled_reverts()
        public
        givenCallbackIsCreated
        givenPoolFee(0)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DirectToLiquidity.Callback_Params_PoolFeeNotEnabled.selector
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_givenUniswapV3PoolAlreadyExists_reverts()
        public
        givenCallbackIsCreated
        givenPoolFee(500)
    {
        // Create the pool
        _uniV3Factory.createPool(address(_baseToken), address(_quoteToken), 500);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(UniswapV3DirectToLiquidity.Callback_Params_PoolExists.selector);
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenStartAndExpiryTimestampsAreTheSame_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_START + 1)
        givenVestingExpiry(_START + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenStartTimestampIsAfterExpiryTimestamp_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_START + 2)
        givenVestingExpiry(_START + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenStartTimestampIsBeforeCurrentTimestamp_succeeds()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_START - 1)
        givenVestingExpiry(_START + 1)
    {
        _performCallback();

        // Assert values
        UniswapV3DirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(configuration.vestingStart, _START - 1, "vestingStart");
        assertEq(configuration.vestingExpiry, _START + 1, "vestingExpiry");
        assertEq(
            address(configuration.linearVestingModule),
            address(_linearVesting),
            "linearVestingModule"
        );

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_whenExpiryTimestampIsBeforeCurrentTimestamp_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_START + 1)
        givenVestingExpiry(_START - 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenVestingSpecified_givenLinearVestingModuleNotInstalled_reverts()
        public
        givenCallbackIsCreated
        givenVestingStart(_START + 1)
        givenVestingExpiry(_START + 2)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DirectToLiquidity.Callback_LinearVestingModuleNotFound.selector
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenVestingSpecified()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_START + 1)
        givenVestingExpiry(_START + 2)
    {
        _performCallback();

        // Assert values
        UniswapV3DirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(configuration.vestingStart, _START + 1, "vestingStart");
        assertEq(configuration.vestingExpiry, _START + 2, "vestingExpiry");
        assertEq(
            address(configuration.linearVestingModule),
            address(_linearVesting),
            "linearVestingModule"
        );

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_givenSendBaseTokens_givenSellerHasInsufficientBalance_reverts()
        public
        givenCallbackSendBaseTokensIsSet
        givenCallbackIsCreated
        givenAddressHasBaseTokenAllowance(_SELLER, address(_dtl), _LOT_CAPACITY)
    {
        _expectTransferFrom();

        _performCallback();
    }

    function test_givenSendBaseTokens_givenSellerHasInsufficientAllowance_reverts()
        public
        givenCallbackSendBaseTokensIsSet
        givenCallbackIsCreated
        givenAddressHasBaseTokenBalance(_SELLER, _LOT_CAPACITY)
    {
        _expectTransferFrom();

        _performCallback();
    }

    function test_givenSendBaseTokens_succeeds()
        public
        givenCallbackSendBaseTokensIsSet
        givenCallbackIsCreated
        givenAddressHasBaseTokenBalance(_SELLER, _LOT_CAPACITY)
        givenAddressHasBaseTokenAllowance(_SELLER, address(_dtl), _LOT_CAPACITY)
    {
        _performCallback();

        // Assert values
        UniswapV3DirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(address(configuration.baseToken), address(_baseToken), "baseToken");
        assertEq(address(configuration.quoteToken), address(_quoteToken), "quoteToken");
        assertEq(configuration.lotCapacity, _LOT_CAPACITY, "lotCapacity");
        assertEq(configuration.lotCuratorPayout, 0, "lotCuratorPayout");
        assertEq(
            configuration.proceedsUtilisationPercent,
            _dtlParams.proceedsUtilisationPercent,
            "proceedsUtilisationPercent"
        );
        assertEq(configuration.poolFee, _dtlParams.poolFee, "poolFee");
        assertEq(configuration.vestingStart, 0, "vestingStart");
        assertEq(configuration.vestingExpiry, 0, "vestingExpiry");
        assertEq(address(configuration.linearVestingModule), address(0), "linearVestingModule");
        assertEq(configuration.active, true, "active");

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_succeeds() public givenCallbackIsCreated {
        _performCallback();

        // Assert values
        UniswapV3DirectToLiquidity.DTLConfiguration memory configuration =
            _getDTLConfiguration(_lotId);
        assertEq(address(configuration.baseToken), address(_baseToken), "baseToken");
        assertEq(address(configuration.quoteToken), address(_quoteToken), "quoteToken");
        assertEq(configuration.lotCapacity, _LOT_CAPACITY, "lotCapacity");
        assertEq(configuration.lotCuratorPayout, 0, "lotCuratorPayout");
        assertEq(
            configuration.proceedsUtilisationPercent,
            _dtlParams.proceedsUtilisationPercent,
            "proceedsUtilisationPercent"
        );
        assertEq(configuration.poolFee, _dtlParams.poolFee, "poolFee");
        assertEq(configuration.vestingStart, 0, "vestingStart");
        assertEq(configuration.vestingExpiry, 0, "vestingExpiry");
        assertEq(address(configuration.linearVestingModule), address(0), "linearVestingModule");
        assertEq(configuration.active, true, "active");

        // Assert balances
        _assertBaseTokenBalances();
    }
}
