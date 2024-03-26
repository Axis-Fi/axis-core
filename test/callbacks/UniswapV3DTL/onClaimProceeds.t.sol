// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

import {IUniswapV3Pool} from "uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {GUniPool} from "g-uni-v1-core/GUniPool.sol";
import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";

import {console2} from "forge-std/console2.sol";

contract UniswapV3DirectToLiquidityOnClaimProceedsTest is UniswapV3DirectToLiquidityTest {
    uint96 internal constant _PROCEEDS = 20e18;
    uint96 internal constant _REFUND = 2e18;

    uint96 internal _proceeds;
    uint96 internal _refund;
    uint96 internal _capacityUtilised;
    uint96 internal _quoteTokensToDeposit;
    uint96 internal _baseTokensToDeposit;
    uint96 internal _curatorPayout;

    uint160 internal constant _SQRT_PRICE_X96_OVERRIDE = 125_270_724_187_523_965_593_206_000_000; // Different to what is normally calculated

    /// @dev Set via `setCallbackParameters` modifier
    uint160 internal _sqrtPriceX96;

    // ========== Assertions ========== //

    function _assertPoolState(uint160 sqrtPriceX96_) internal {
        // Get the pool
        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));
        address pool = _uniV3Factory.getPool(token0, token1, _dtlCreateParams.poolFee);

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        assertEq(sqrtPriceX96, sqrtPriceX96_, "pool sqrt price");
    }

    function _assertLpTokenBalance() internal {
        // TODO vesting

        // Get the pools deployed by the DTL callback
        address[] memory pools = _gUniFactory.getPools(_dtlAddress);
        assertEq(pools.length, 1, "pools length");
        GUniPool pool = GUniPool(pools[0]);

        assertEq(pool.balanceOf(_SELLER), pool.totalSupply(), "seller: LP token balance");
    }

    function _assertQuoteTokenBalance() internal {
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "DTL: quote token balance");
    }

    function _assertBaseTokenBalance() internal {
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "DTL: base token balance");
    }

    // ========== Modifiers ========== //

    function _performCallback() internal {
        vm.prank(address(_auctionHouse));
        _dtl.onClaimProceeds(_lotId, _proceeds, _refund, abi.encode(""));
    }

    function _createPool() internal returns (address) {
        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));

        return _uniV3Factory.createPool(token0, token1, _dtlCreateParams.poolFee);
    }

    function _initializePool(address pool_, uint160 sqrtPriceX96_) internal {
        IUniswapV3Pool(pool_).initialize(sqrtPriceX96_);
    }

    modifier givenPoolIsCreated() {
        _createPool();
        _;
    }

    modifier givenPoolIsCreatedAndInitialized(uint160 sqrtPriceX96_) {
        address pool = _createPool();
        _initializePool(pool, sqrtPriceX96_);
        _;
    }

    function _calculateSqrtPriceX96(
        uint256 quoteTokenAmount_,
        uint256 baseTokenAmount_
    ) internal view returns (uint160) {
        return SqrtPriceMath.getSqrtPriceX96(
            address(_quoteToken), address(_baseToken), quoteTokenAmount_, baseTokenAmount_
        );
    }

    modifier setCallbackParameters(uint96 proceeds_, uint96 refund_) {
        _proceeds = proceeds_;
        _refund = refund_;

        // Calculate the capacity utilised
        // Any unspent curator payout is included in the refund
        // However, curator payouts are linear to the capacity utilised
        // Calculate the percent utilisation
        uint96 capacityUtilisationPercent = 1e5 - _refund * 1e5 / (_LOT_CAPACITY + _curatorPayout);
        _capacityUtilised = _LOT_CAPACITY * capacityUtilisationPercent / 1e5;

        // The proceeds utilisation percent scales the quote tokens and base tokens linearly
        _quoteTokensToDeposit = _proceeds * _dtlCreateParams.proceedsUtilisationPercent / 1e5;
        _baseTokensToDeposit = _capacityUtilised * _dtlCreateParams.proceedsUtilisationPercent / 1e5;

        _sqrtPriceX96 = _calculateSqrtPriceX96(_quoteTokensToDeposit, _baseTokensToDeposit);
        _;
    }

    modifier givenUnboundedProceedsUtilisationPercent(uint24 percent_) {
        // Bound the percent
        uint24 percent = uint24(bound(percent_, 1, 1e5));

        // Set the value on the DTL
        _dtlCreateParams.proceedsUtilisationPercent = percent;
        _;
    }

    modifier givenUnboundedOnCurate(uint96 curationPayout_) {
        // Bound the value
        _curatorPayout = uint96(bound(curationPayout_, 1e17, _LOT_CAPACITY));

        // Call the onCurate callback
        _performOnCurate(_curatorPayout);
        _;
    }

    // ========== Tests ========== //

    // [X] given the pool is created
    //  [X] it initializes the pool
    // [X] given the pool is created and initialized
    //  [X] it succeeds
    // [X] given the proceeds utilisation percent is set
    //  [X] it calculates the deposit amount correctly
    // [X] given curation is enabled
    //  [X] the utilisation percent considers this
    // [ ] when the refund amount changes
    //  [ ] the utilisation percent considers this
    // [ ] given minting pool tokens utilises less than the available amount of base tokens
    //  [ ] the excess base tokens are returned
    // [ ] given minting pool tokens utilises less than the available amount of quote tokens
    //  [ ] the excess quote tokens are returned
    // [ ] given the send base tokens flag is false
    //  [ ] it transfers the base tokens from the seller
    // [ ] given the send base tokens flag is true
    //  [ ] when the refund amount is less than the base tokens required
    //   [ ] it transfers the base tokens from the seller
    // [ ] given vesting is enabled
    //  [ ] it mints the vesting tokens to the seller
    // [ ] it creates and initializes the pool, creates a pool token, deposits into the pool token, transfers the LP token to the seller and transfers any excess back to the seller

    function test_givenPoolIsCreated()
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performCallback();

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
    }

    function test_givenPoolIsCreatedAndInitialized()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolIsCreatedAndInitialized(_SQRT_PRICE_X96_OVERRIDE)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performCallback();

        _assertPoolState(_SQRT_PRICE_X96_OVERRIDE);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
    }

    function test_givenProceedsUtilisationPercent_fuzz(uint24 percent_)
        public
        givenCallbackIsCreated
        givenUnboundedProceedsUtilisationPercent(percent_)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performCallback();

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
    }

    function test_givenCurationPayout_fuzz(uint96 curationPayout_)
        public
        givenCallbackIsCreated
        givenOnCreate
        givenUnboundedOnCurate(curationPayout_)
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performCallback();

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
    }

    function test_givenProceedsUtilisationPercent_givenCurationPayout_fuzz(
        uint24 percent_,
        uint96 curationPayout_
    )
        public
        givenCallbackIsCreated
        givenUnboundedProceedsUtilisationPercent(percent_)
        givenOnCreate
        givenUnboundedOnCurate(curationPayout_)
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performCallback();

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
    }
}
