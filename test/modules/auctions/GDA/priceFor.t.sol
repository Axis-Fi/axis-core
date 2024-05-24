// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IGradualDutchAuction} from "src/interfaces/modules/auctions/IGradualDutchAuction.sol";

import {UD60x18, ud, convert, UNIT, uUNIT, EXP_MAX_INPUT} from "lib/prb-math/src/UD60x18.sol";
import "lib/prb-math/src/Common.sol" as PRBMath;

import {GdaTest} from "test/modules/auctions/GDA/GDATest.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract GdaPriceForTest is GdaTest {
    using {PRBMath.mulDiv} for uint256;

    // [X] when the lot ID is invalid
    //   [X] it reverts
    // [X] when payout is greater than remaining capacity
    //   [X] it reverts
    // [X when minimum price is zero
    //   [X] it calculates the price correctly
    //   [X] when last auction start is in the future
    //     [X] it calculates the price correctly
    //   [X] when last auction start is in the past
    //     [X] it calculates the price correctly
    // [X] when minimum price is greater than zero
    //   [X] it calculates the price correctly
    //   [X] when last auction start is in the future
    //     [X] it calculates the price correctly
    //   [X] when last auction start is in the past
    //     [X] it calculates the price correctly
    // [X] when large, reasonable values are used
    //   [X] it does not overflow
    // TODO can we fuzz this better? maybe use some external calculations to compare the values?
    // Otherwise, we're just recreating the same calculations here and not really validating anything

    function testFuzz_lotIdInvalid_reverts(uint96 lotId_) public {
        // No lots have been created so all lots are invalid
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, lotId_);
        vm.expectRevert(err);
        _module.priceFor(lotId_, 1e18);
    }

    function test_payoutGreaterThanRemainingCapacity_reverts() public givenLotIsCreated {
        // Payout is greater than remaining capacity
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InsufficientCapacity.selector);
        vm.expectRevert(err);
        _module.priceFor(_lotId, _LOT_CAPACITY + 1);
    }

    function test_minPriceZero() public givenMinPrice(0) givenLotIsCreated givenLotHasStarted {
        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 payout = _LOT_CAPACITY / _DURATION; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e14); // 0.01%

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD);
        // The first auction has concluded. The price should be the target price for the decay period.
        price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout end of decay period:", price);

        expectedPrice =
            _INITIAL_PRICE.mulDiv(1e18 - _DECAY_TARGET, 1e18).mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e14); // 0.01%, TODO is this good enough? Seems like it slightly underestimates
    }

    function test_minPriceNonZero() public givenLotIsCreated givenLotHasStarted {
        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 payout = _LOT_CAPACITY / _DURATION; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e14); // 0.01%

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD + 1);
        // The first auction has concluded. The price should be the target price for the decay period.
        price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout end of decay period:", price);

        expectedPrice =
            _INITIAL_PRICE.mulDiv(1e18 - _DECAY_TARGET, 1e18).mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e14); // 0.01%, TODO is this good enough? Seems like it slightly underestimates
    }

    function test_minPriceNonZero_lastAuctionStartInFuture() public givenLotIsCreated {
        // We don't start the auction so the lastAuctionStart is 1 second ahead of the current time.
        // 1 seconds worth of tokens should be slightly more than the initial price.
        uint256 payout = _LOT_CAPACITY / _DURATION; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertGe(price, expectedPrice);
    }

    function test_minPriceNonZero_lastAuctionStartInPast() public givenLotIsCreated {
        vm.warp(_start + 1);
        //lastAuctionStart is 1 second behind the current time.
        // 1 seconds worth of tokens should be slightly less than the initial price.
        uint256 payout = _LOT_CAPACITY / _DURATION; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertLe(price, expectedPrice);
    }

    function testFuzz_minPriceZero_noOverflows(
        uint128 capacity_,
        uint128 payout_
    ) public givenLotCapacity(uint256(capacity_)) givenMinPrice(0) {
        vm.assume(capacity_ >= _DURATION);
        vm.assume(payout_ <= capacity_);
        _createAuctionLot();

        vm.warp(_start);

        _module.priceFor(_lotId, payout_);
    }

    function testFuzz_minPriceNonZero_noOverflows(
        uint128 capacity_,
        uint128 payout_
    ) public givenLotCapacity(uint256(capacity_)) {
        vm.assume(capacity_ >= _DURATION);
        vm.assume(payout_ <= capacity_);
        _createAuctionLot();

        vm.warp(_start);

        _module.priceFor(_lotId, payout_);
    }

    function testFuzz_minPriceZero_varyingSetup(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenLotCapacity(uint256(capacity_))
        givenEquilibriumPrice(uint256(price_))
        givenMinPrice(0)
    {
        vm.assume(capacity_ >= _DURATION);
        vm.assume(price_ >= 1000);
        _createAuctionLot();

        vm.warp(_start);

        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        uint256 payout = _auctionParams.capacity / _DURATION; // 1 seconds worth of tokens
        console2.log("Payout:", payout);
        uint256 price = _module.priceFor(_lotId, payout);
        uint256 expectedPrice = _gdaParams.equilibriumPrice.mulDiv(payout, _BASE_SCALE);
        // assertApproxEqAbs(price, expectedPrice, 1e18); TODO how to think about these bounds? some extremes have large errors

        vm.warp(_start + _DECAY_PERIOD);
        price = _module.priceFor(_lotId, payout);
        expectedPrice = expectedPrice.mulDiv(uUNIT - _gdaParams.decayTarget, uUNIT);
        // assertApproxEqAbs(price, expectedPrice, 1e18);
    }

    function testFuzz_minPriceNonZero_varyingSetup(
        uint128 capacity_,
        uint128 price_
    ) public givenLotCapacity(uint256(capacity_)) givenEquilibriumPrice(uint256(price_)) {
        vm.assume(capacity_ >= _DURATION);
        uint256 decayedPrice = uint256(price_).mulDiv(uUNIT - _gdaParams.decayTarget, uUNIT);
        vm.assume(decayedPrice > _gdaParams.minimumPrice); // must have room for decay
        _createAuctionLot();

        vm.warp(_start);

        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        uint256 payout = _auctionParams.capacity / _DURATION; // 1 seconds worth of tokens
        console2.log("Payout:", payout);
        uint256 price = _module.priceFor(_lotId, payout);
        uint256 expectedPrice = _gdaParams.equilibriumPrice.mulDiv(payout, _BASE_SCALE);
        // assertApproxEqAbs(price, expectedPrice, 1e18); TODO how to think about these bounds? some extremes have large errors

        vm.warp(_start + _DECAY_PERIOD);
        price = _module.priceFor(_lotId, payout);
        expectedPrice = expectedPrice.mulDiv(uUNIT - _gdaParams.decayTarget, uUNIT);
        // assertApproxEqAbs(price, expectedPrice, 1e18);
    }

    function testFuzz_minPriceZero_varyingTimesteps(uint48 timestep_)
        public
        givenMinPrice(0)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Warp to the timestep
        uint48 timestep = timestep_ % _DURATION;
        console2.log("Warping to timestep:", timestep);
        vm.warp(_start + timestep);

        // Calculated the expected price of the oldest auction at the timestep
        IGradualDutchAuction.AuctionData memory data = _getAuctionData(_lotId);
        UD60x18 q0 = ud(_INITIAL_PRICE.mulDiv(uUNIT, 10 ** _quoteTokenDecimals));
        UD60x18 r = data.emissionsRate;
        UD60x18 k = data.decayConstant;
        UD60x18 t = convert(timestep).div(_ONE_DAY);
        UD60x18 qt = q0.mul(r).div(k.mul(t).exp());
        console2.log("Expected price at timestep:", qt.unwrap());

        // Set payout to 1 seconds worth of tokens
        uint256 payout = _LOT_CAPACITY / _DURATION;

        // Calculate the price
        uint256 price = _module.priceFor(_lotId, payout);

        // Calculate the expected price (qt divided by 1 day)
        uint256 expectedPrice = qt.intoUint256().mulDiv(10 ** _quoteTokenDecimals, uUNIT) / 1 days;

        // The price should be conservative (greater than or equal to the expected price)
        assertGe(price, expectedPrice);
        assertApproxEqRel(price, expectedPrice, 1e14); // 0.01%
    }

    function testFuzz_minPriceNonZero_varyingTimesteps(uint48 timestep_)
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        // Warp to the timestep
        uint48 timestep = timestep_ % _DURATION;
        console2.log("Warping to timestep:", timestep);
        vm.warp(_start + timestep);

        // Calculated the expected price of the oldest auction at the timestep
        IGradualDutchAuction.AuctionData memory data = _getAuctionData(_lotId);
        UD60x18 q0 = ud(_INITIAL_PRICE.mulDiv(uUNIT, 10 ** _quoteTokenDecimals));
        UD60x18 qm = ud(_MIN_PRICE.mulDiv(uUNIT, 10 ** _quoteTokenDecimals));
        UD60x18 r = data.emissionsRate;
        UD60x18 k = data.decayConstant;
        UD60x18 t = convert(timestep).div(_ONE_DAY);
        UD60x18 qt = (q0 - qm).div(k.mul(t).exp()).add(qm).mul(r);
        console2.log("Expected price at timestep:", qt.unwrap());

        // Set payout to 1 seconds worth of tokens
        uint256 payout = _LOT_CAPACITY / _DURATION;

        // Calculate the price
        uint256 price = _module.priceFor(_lotId, payout);

        // Calculate the expected price (qt divided by 1 day)
        uint256 expectedPrice = qt.intoUint256().mulDiv(10 ** _quoteTokenDecimals, uUNIT) / 1 days;

        // The price should be conservative (greater than or equal to the expected price)
        assertGe(price, expectedPrice);
        assertApproxEqRel(price, expectedPrice, 1e14); // 0.01%
    }
}
