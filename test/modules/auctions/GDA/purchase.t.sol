// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "../../../../src/modules/Modules.sol";
import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {IGradualDutchAuction} from
    "../../../../src/interfaces/modules/auctions/IGradualDutchAuction.sol";

import {
    UD60x18, ud, convert, UNIT, uUNIT, ZERO, EXP_MAX_INPUT
} from "prb-math-4.0-axis/UD60x18.sol";
import "prb-math-4.0-axis/Common.sol" as PRBMath;

import {GdaTest} from "./GDATest.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";

contract GdaPurchaseTest is GdaTest {
    using {PRBMath.mulDiv} for uint256;

    uint256 internal _purchaseAmount = 5e18;
    uint256 internal _purchaseAmountOut;

    modifier setPurchaseAmount(
        uint256 amount
    ) {
        _purchaseAmount = amount;
        _;
    }

    modifier setAmountOut() {
        _purchaseAmountOut = _module.payoutFor(_lotId, _purchaseAmount);
        _;
    }

    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction has concluded
    //  [X] it reverts
    // [X] when the auction has been cancelled
    //  [X] it reverts
    // [X] when the auction has not started
    //  [X] it reverts
    // [X] when there is insufficient capacity
    //  [X] it reverts
    // [X] when the amount is more than the max amount accepted
    //  [X] it reverts
    // [X] when the token decimals are different
    //  [X] it handles the purchase correctly
    // [X] it updates the capacity, purchased, sold, and last auction start

    function test_notParent_reverts() public givenLotIsCreated givenLotHasStarted setAmountOut {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function
        _module.purchase(_lotId, _purchaseAmount, abi.encode(_purchaseAmountOut));
    }

    function test_invalidLotId_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_purchaseAmount, _purchaseAmountOut);
    }

    function test_auctionConcluded_reverts()
        public
        givenLotIsCreated
        givenLotHasConcluded
        setAmountOut
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_purchaseAmount, _purchaseAmountOut);
    }

    function test_auctionCancelled_reverts()
        public
        givenLotIsCreated
        setAmountOut
        givenLotIsCancelled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_purchaseAmount, _purchaseAmountOut);
    }

    function test_auctionNotStarted_reverts() public givenLotIsCreated setAmountOut {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_purchaseAmount, _purchaseAmountOut);
    }

    function test_whenCapacityIsInsufficient_reverts()
        public
        givenLotCapacity(15e17)
        givenLotIsCreated
        givenLotHasStarted
        setAmountOut
        givenPurchase(_purchaseAmount, _purchaseAmountOut) // Payout ~0.95, remaining capacity is 1.5 - 0.95 = 0.55
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InsufficientCapacity.selector);
        vm.expectRevert(err);

        // Call the function
        _createPurchase(_purchaseAmount, _purchaseAmountOut);
    }

    function testFuzz_amountGreaterThanMaxAccepted_reverts(
        uint256 amount_
    ) public givenLotIsCreated givenLotHasStarted {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        vm.assume(amount_ > maxAmountAccepted);

        // Expect revert (may fail due to math issues or the capacity check)
        vm.expectRevert();

        // Call the function
        _createPurchase(amount_, 0); // We don't set the minAmountOut slippage check since trying to calculate the payout would revert
    }

    function testFuzz_minPriceNonZero_success(
        uint256 amount_
    ) public givenLotIsCreated givenLotHasStarted {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);
        console2.log("amount", amount);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceNonZero_success_quoteTokenDecimalsLarger(
        uint256 amount_
    )
        public
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceNonZero_success_quoteTokenDecimalsSmaller(
        uint256 amount_
    )
        public
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceNonZero_afterDecay_success(
        uint256 amount_
    ) public givenLotIsCreated {
        // Warp forward in time to late in the auction
        vm.warp(_start + _DURATION - 1 hours);

        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    // Limit capacity to u128 here so it uses reasonable values
    function testFuzz_minPriceNonZero_varyingSetup(
        uint256 amount_,
        uint128 capacity_,
        uint128 price_
    )
        public
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
        givenLotHasStarted
    {
        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        // Normalize the amount
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, uint256(capacity_) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceNonZero_varyingSetup_quoteDecimalsSmaller(
        uint256 amount_,
        uint128 capacity_,
        uint128 price_
    )
        public
        givenQuoteTokenDecimals(6)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
        givenLotHasStarted
    {
        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        // Normalize the amount
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, uint256(capacity_) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceNonZero_varyingSetup_quoteDecimalsLarger(
        uint256 amount_,
        uint128 capacity_,
        uint128 price_
    )
        public
        givenBaseTokenDecimals(6)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
        givenLotHasStarted
    {
        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        // Normalize the amount
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, uint256(capacity_) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceZero_success(
        uint256 amount_
    ) public givenMinPrice(0) givenLotIsCreated givenLotHasStarted {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);
        console2.log("amount", amount);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceZero_success_quoteTokenDecimalsLarger(
        uint256 amount_
    )
        public
        givenMinPrice(0)
        givenQuoteTokenDecimals(17)
        givenBaseTokenDecimals(13)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceZero_success_quoteTokenDecimalsSmaller(
        uint256 amount_
    )
        public
        givenMinPrice(0)
        givenQuoteTokenDecimals(13)
        givenBaseTokenDecimals(17)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceZero_afterDecay_success(
        uint256 amount_
    ) public givenMinPrice(0) givenLotIsCreated {
        // Warp forward in time to late in the auction
        vm.warp(_start + _DURATION - 1 hours);

        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, _scaleBaseTokenAmount(_LOT_CAPACITY) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    // Limit capacity to u128 here so it uses reasonable values
    function testFuzz_minPriceZero_varyingSetup(
        uint256 amount_,
        uint128 capacity_,
        uint128 price_
    )
        public
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinPrice(0)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
        givenLotHasStarted
    {
        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        // Normalize the amount
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, uint256(capacity_) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceZero_varyingSetup_quoteDecimalsSmaller(
        uint256 amount_,
        uint128 capacity_,
        uint128 price_
    )
        public
        givenQuoteTokenDecimals(6)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinPrice(0)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
        givenLotHasStarted
    {
        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        // Normalize the amount
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, uint256(capacity_) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }

    function testFuzz_minPriceZero_varyingSetup_quoteDecimalsLarger(
        uint256 amount_,
        uint128 capacity_,
        uint128 price_
    )
        public
        givenBaseTokenDecimals(6)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinPrice(0)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
        givenLotHasStarted
    {
        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        // Normalize the amount
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 amount = amount_ % (maxAmountAccepted + 1);

        // Calculate expected values
        uint256 expectedPayout = _module.payoutFor(_lotId, amount);

        // Call the function
        _createPurchase(amount, expectedPayout);

        // Assert the capacity, purchased and sold
        IAuction.Lot memory lot = _getAuctionLot(_lotId);
        assertEq(lot.capacity, uint256(capacity_) - expectedPayout, "capacity");
        assertEq(lot.purchased, amount, "purchased");
        assertEq(lot.sold, expectedPayout, "sold");
    }
}
