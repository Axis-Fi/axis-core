// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {IGradualDutchAuction} from
    "../../../../src/interfaces/modules/auctions/IGradualDutchAuction.sol";

import {UD60x18, ud, convert, uUNIT} from "prb-math-4.0-axis/UD60x18.sol";
import "prb-math-4.0-axis/Common.sol" as PRBMath;

import {GdaTest} from "./GDATest.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";

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
    // [X] when the quote token decimals are larger than the base token decimals
    //   [X] when the minimum price is zero
    //     [X] it calculates the price correctly
    //   [X] when the minimum price is non-zero
    //     [X] it calculates the price correctly
    // [X] when the quote token decimals are smaller than the base token decimals
    //   [X] when the minimum price is zero
    //     [X] it calculates the price correctly
    //   [X] when the minimum price is non-zero
    //     [X] it calculates the price correctly
    // TODO can we fuzz this better? maybe use some external calculations to compare the values?
    // Otherwise, we're just recreating the same calculations here and not really validating anything

    function testFuzz_lotIdInvalid_reverts(
        uint96 lotId_
    ) public {
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
        uint256 payout = _LOT_CAPACITY / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD);
        // The first auction has concluded. The price should be the target price for the decay period.
        price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout end of decay period:", price);

        expectedPrice =
            _INITIAL_PRICE.mulDiv(1e18 - _DECAY_TARGET, 1e18).mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%, TODO is this good enough? Seems like it slightly underestimates
    }

    function test_minPriceNonZero() public givenLotIsCreated givenLotHasStarted {
        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 payout = _LOT_CAPACITY / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD + 1);
        // The first auction has concluded. The price should be the target price for the decay period.
        price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout end of decay period:", price);

        expectedPrice =
            _INITIAL_PRICE.mulDiv(1e18 - _DECAY_TARGET, 1e18).mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%, TODO is this good enough? Seems like it slightly underestimates
    }

    function test_minPriceNonZero_lastAuctionStartInFuture() public givenLotIsCreated {
        // We don't start the auction so the lastAuctionStart is 1 second ahead of the current time.
        // 1 seconds worth of tokens should be slightly more than the initial price.
        uint256 payout = _LOT_CAPACITY / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
        console2.log("Expected price:", expectedPrice);

        assertGe(price, expectedPrice);
    }

    function test_minPriceNonZero_lastAuctionStartInPast() public givenLotIsCreated {
        vm.warp(_start + 1000);
        // lastAuctionStart is 1000 seconds behind the current time.
        // We have to go further than 1 second due to the error correction in priceFor,
        // which increases the estimate slightly.
        // 1 seconds worth of tokens should be slightly less than the initial price.
        uint256 payout = _LOT_CAPACITY / _auctionParams.duration; // 1 seconds worth of tokens
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
    )
        public
        givenLotCapacity(capacity_)
        givenMinPrice(0)
        validateCapacity
        givenLotIsCreated
        givenLotHasStarted
    {
        vm.assume(payout_ <= capacity_);

        _module.priceFor(_lotId, payout_);
    }

    function testFuzz_minPriceNonZero_noOverflows(
        uint128 capacity_,
        uint128 payout_
    ) public givenLotCapacity(capacity_) validateCapacity givenLotIsCreated givenLotHasStarted {
        vm.assume(payout_ <= capacity_);

        _module.priceFor(_lotId, payout_);
    }

    function testFuzz_minPriceZero_varyingSetup(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenDuration(1 days)
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

        uint256 payout = _auctionParams.capacity / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("Payout:", payout);
        uint256 price = _module.priceFor(_lotId, payout);
        uint256 expectedPrice = _gdaParams.equilibriumPrice.mulDiv(payout, _BASE_SCALE);
        assertGe(price, expectedPrice);

        vm.warp(_start + _DECAY_PERIOD);
        price = _module.priceFor(_lotId, payout);
        expectedPrice = expectedPrice.mulDiv(uUNIT - _gdaParams.decayTarget, uUNIT);
        assertGe(price, expectedPrice);
    }

    function testFuzz_minPriceNonZero_varyingSetup(
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
        // // Validate price is slightly higher than needed to avoid uncorrected errors in tiny
        // // amounts from causing the test to fail.
        // vm.assume(price_ >= 1e4 * 10 ** ((_quoteTokenDecimals / 2) + (_quoteTokenDecimals % 2 == 0 ? 0 : 1)));
        // _createAuctionLot();
        // vm.warp(_start);

        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        uint256 payout = _auctionParams.capacity / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("Payout:", payout);
        uint256 price = _module.priceFor(_lotId, payout);
        uint256 expectedPrice = _gdaParams.equilibriumPrice.mulDiv(payout, _BASE_SCALE);
        assertGe(price, expectedPrice);

        vm.warp(_start + _gdaParams.decayPeriod);
        price = _module.priceFor(_lotId, payout);
        expectedPrice = expectedPrice.mulDiv(uUNIT - _gdaParams.decayTarget, uUNIT);
        assertGe(price, expectedPrice);
    }

    function testFuzz_minPriceZero_varyingTimesteps(
        uint48 timestep_
    ) public givenMinPrice(0) givenLotIsCreated givenLotHasStarted {
        // Warp to the timestep
        uint48 timestep = timestep_ % _auctionParams.duration;
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
        uint256 payout = _LOT_CAPACITY / _auctionParams.duration;

        // Calculate the price
        uint256 price = _module.priceFor(_lotId, payout);

        // Calculate the expected price (qt divided by 1 day)
        uint256 expectedPrice = qt.intoUint256().mulDiv(10 ** _quoteTokenDecimals, uUNIT) / 1 days;

        // The price should be conservative (greater than or equal to the expected price)
        assertGe(price, expectedPrice);
        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%
    }

    function testFuzz_minPriceNonZero_varyingTimesteps(
        uint48 timestep_
    ) public givenLotIsCreated givenLotHasStarted {
        // Warp to the timestep
        uint48 timestep = timestep_ % _auctionParams.duration;
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
        uint256 payout = _LOT_CAPACITY / _auctionParams.duration;

        // Calculate the price
        uint256 price = _module.priceFor(_lotId, payout);

        // Calculate the expected price (qt divided by 1 day)
        uint256 expectedPrice = qt.intoUint256().mulDiv(10 ** _quoteTokenDecimals, uUNIT) / 1 days;

        // The price should be conservative (greater than or equal to the expected price)
        assertGe(price, expectedPrice);
        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%
    }

    function test_givenQuoteTokenDecimalsLarger_minPriceNonZero()
        public
        givenBaseTokenDecimals(9)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 baseTokenScale = 10 ** 9;
        uint256 quoteTokenScale = 10 ** 18;
        uint256 initialPrice = _INITIAL_PRICE * quoteTokenScale / 10 ** 18;

        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 payout = (_LOT_CAPACITY * baseTokenScale / 10 ** 18) / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = initialPrice.mulDiv(payout, baseTokenScale);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD + 1);
        // The first auction has concluded. The price should be the target price for the decay period.
        price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout end of decay period:", price);

        expectedPrice =
            initialPrice.mulDiv(1e18 - _DECAY_TARGET, 1e18).mulDiv(payout, baseTokenScale);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%, TODO is this good enough? Seems like it slightly underestimates
    }

    function test_givenQuoteTokenDecimalsSmaller_minPriceNonZero()
        public
        givenQuoteTokenDecimals(9)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 baseTokenScale = 10 ** 18;
        uint256 quoteTokenScale = 10 ** 9;
        uint256 initialPrice = _INITIAL_PRICE * quoteTokenScale / 10 ** 18;

        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 payout = (_LOT_CAPACITY * baseTokenScale / 10 ** 18) / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = initialPrice.mulDiv(payout, baseTokenScale);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD + 1);
        // The first auction has concluded. The price should be the target price for the decay period.
        price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout end of decay period:", price);

        expectedPrice =
            initialPrice.mulDiv(1e18 - _DECAY_TARGET, 1e18).mulDiv(payout, baseTokenScale);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%, TODO is this good enough? Seems like it slightly underestimates
    }

    function test_givenQuoteTokenDecimalsLarger_minPriceZero()
        public
        givenBaseTokenDecimals(9)
        givenMinPrice(0)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 baseTokenScale = 10 ** 9;
        uint256 quoteTokenScale = 10 ** 18;
        uint256 initialPrice = _INITIAL_PRICE * quoteTokenScale / 10 ** 18;

        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 payout = (_LOT_CAPACITY * baseTokenScale / 10 ** 18) / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = initialPrice.mulDiv(payout, baseTokenScale);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD + 1);
        // The first auction has concluded. The price should be the target price for the decay period.
        price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout end of decay period:", price);

        expectedPrice =
            initialPrice.mulDiv(1e18 - _DECAY_TARGET, 1e18).mulDiv(payout, baseTokenScale);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%, TODO is this good enough? Seems like it slightly underestimates
    }

    function test_givenQuoteTokenDecimalsSmaller_minPriceZero()
        public
        givenQuoteTokenDecimals(9)
        givenMinPrice(0)
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 baseTokenScale = 10 ** 18;
        uint256 quoteTokenScale = 10 ** 9;
        uint256 initialPrice = _INITIAL_PRICE * quoteTokenScale / 10 ** 18;

        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 payout = (_LOT_CAPACITY * baseTokenScale / 10 ** 18) / _auctionParams.duration; // 1 seconds worth of tokens
        console2.log("1 second of token emissions:", payout);

        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        uint256 expectedPrice = initialPrice.mulDiv(payout, baseTokenScale);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD + 1);
        // The first auction has concluded. The price should be the target price for the decay period.
        price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout end of decay period:", price);

        expectedPrice =
            initialPrice.mulDiv(1e18 - _DECAY_TARGET, 1e18).mulDiv(payout, baseTokenScale);
        console2.log("Expected price:", expectedPrice);

        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%, TODO is this good enough? Seems like it slightly underestimates
    }

    function test_minPriceNonZero_initialTimestep_largeAmount()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        // Set desired payout to be close to the lot capacity
        uint256 payout = 9e18;

        IGradualDutchAuction.AuctionData memory data = _getAuctionData(_lotId);
        console2.log("Emissions rate:", data.emissionsRate.unwrap());
        console2.log("Decay constant:", data.decayConstant.unwrap());

        // Calculate the expected price
        // Given: Q(T) = (r * (q0 - qm) * (e^((k*P)/r) - 1)) / ke^(k*T) + (qm * P)
        // We know:
        // r = 5e18
        // q0 = 5e18
        // qm = 2.5e18
        // k = 446287102628419492
        // T = 0
        // P = 9e18
        // Q(T) = (5e18 * ((5e18 - 2.5e18)/1e18) * (e^((446287102628419492 * 9e18)/5e18) - 1e18)) / (446287102628419492 * e^(446287102628419492 * 0)) + (2.5e18 * 9e18 / 1e18)
        // Q(T) = 1.6991124264×10^19
        uint256 expectedPrice = 1.6991124264e19;

        // Calculate the price
        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        // TODO figure out why this is 57033118271917796895
        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%
    }

    function test_minPriceZero_initialTimestep_largeAmount()
        public
        givenMinPrice(0)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Set desired payout to be close to the lot capacity
        uint256 payout = 9e18;

        IGradualDutchAuction.AuctionData memory data = _getAuctionData(_lotId);
        console2.log("Emissions rate:", data.emissionsRate.unwrap());
        console2.log("Decay constant:", data.decayConstant.unwrap());

        // Calculate the expected price
        // Given: Q(T) = (r * q0 * (e^((k*P)/r) - 1)) / ke^(k*T)
        // We know:
        // r = 5e18
        // q0 = 5e18
        // qm = 2.5e18
        // k = 210721031315652584
        // T = 0
        // P = 9e18
        // Q(T) = (5e18 * ((5e18 - 2.5e18)/1e18) * (e^((210721031315652584 * 9e18)/5e18) - 1e18)) / (210721031315652584 * e^(210721031315652584 * 0))
        // Q(T) = -3.6820134881×10^19

        // Expect underflow
        vm.expectRevert("arithmetic overflow/underflow");

        // Calculate the price
        _module.priceFor(_lotId, payout);

        // TODO figure out why this is 54723799175963968489
    }

    function test_minPriceNonZero_dayTwo_largeAmount()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        // Warp to the second day
        uint48 timestamp = _start + 1 days;
        vm.warp(timestamp);

        // Set desired payout to be close to the lot capacity
        uint256 payout = 9e18;

        IGradualDutchAuction.AuctionData memory data = _getAuctionData(_lotId);
        console2.log("Emissions rate:", data.emissionsRate.unwrap());
        console2.log("Decay constant:", data.decayConstant.unwrap());

        // Calculate the expected price
        // Given: Q(T) = (r * (q0 - qm) * (e^((k*P)/r) - 1)) / ke^(k*T) + (qm * P)
        // We know:
        // r = 5e18
        // q0 = 5e18
        // qm = 2.5e18
        // k = 446287102628419492
        // T = 1 (day)
        // P = 9e18
        // Q(T) = (5e18 * ((5e18 - 2.5e18)/1e18) * (e^((446287102628419492 * 9e18)/5e18) - 1e18)) / (446287102628419492 * e^(446287102628419492 * 1)) + (2.5e18 * 9e18 / 1e18)
        // Q(T) = 2.25e19
        uint256 expectedPrice = 2.25e19;

        // Calculate the price
        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        // TODO figure out why this is 44601195694027390496
        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%
    }

    function test_minPriceZero_dayTwo_largeAmount()
        public
        givenMinPrice(0)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Warp to the second day
        uint48 timestamp = _start + 1 days;
        vm.warp(timestamp);

        // Set desired payout to be close to the lot capacity
        uint256 payout = 9e18;

        IGradualDutchAuction.AuctionData memory data = _getAuctionData(_lotId);
        console2.log("Emissions rate:", data.emissionsRate.unwrap());
        console2.log("Decay constant:", data.decayConstant.unwrap());

        // Calculate the expected price
        // Given: Q(T) = (r * q0 * (e^((k*P)/r) - 1)) / ke^(k*T)
        // We know:
        // r = 5e18
        // q0 = 5e18
        // qm = 2.5e18
        // k = 210721031315652584
        // T = 1 (day)
        // P = 9e18
        // Q(T) = (5e18 * ((5e18 - 2.5e18)/1e18) * (e^((210721031315652584 * 9e18)/5e18) - 1e18)) / (210721031315652584 * e^(210721031315652584 * 1))
        // Q(T) = -174.7340294016

        // Expect underflow
        vm.expectRevert("arithmetic overflow/underflow");

        // Calculate the price
        _module.priceFor(_lotId, payout);

        // TODO figure out why this is 44326277332530815351
    }

    function test_minPriceNonZero_lastDay_largeAmount()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        // Warp to the last day
        uint48 timestamp = _start + 2 days;
        vm.warp(timestamp);

        // Set desired payout to be close to the lot capacity
        uint256 payout = 9e18;

        IGradualDutchAuction.AuctionData memory data = _getAuctionData(_lotId);
        console2.log("Emissions rate:", data.emissionsRate.unwrap());
        console2.log("Decay constant:", data.decayConstant.unwrap());

        // Calculate the expected price
        // Given: Q(T) = (r * (q0 - qm) * (e^((k*P)/r) - 1)) / ke^(k*T) + (qm * P)
        // We know:
        // r = 5e18
        // q0 = 5e18
        // qm = 2.5e18
        // k = 446287102628419492
        // T = 2 (day)
        // P = 9e18
        // Q(T) = (5e18 * ((5e18 - 2.5e18)/1e18) * (e^((446287102628419492 * 9e18)/5e18) - 1e18)) / (446287102628419492 * e^(446287102628419492 * 2)) + (2.5e18 * 9e18 / 1e18)
        // Q(T) = 2.25e19
        uint256 expectedPrice = 2.25e19;

        // Calculate the price
        uint256 price = _module.priceFor(_lotId, payout);
        console2.log("Price for payout at beginning:", price);

        // TODO figure out why this is 36644765244177530185
        assertApproxEqRel(price, expectedPrice, 1e15); // 0.1%
    }

    function test_minPriceZero_lastDay_largeAmount()
        public
        givenMinPrice(0)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Warp to the last day
        uint48 timestamp = _start + 2 days;
        vm.warp(timestamp);

        // Set desired payout to be close to the lot capacity
        uint256 payout = 9e18;

        IGradualDutchAuction.AuctionData memory data = _getAuctionData(_lotId);
        console2.log("Emissions rate:", data.emissionsRate.unwrap());
        console2.log("Decay constant:", data.decayConstant.unwrap());

        // Calculate the expected price
        // Given: Q(T) = (r * q0 * (e^((k*P)/r) - 1)) / ke^(k*T)
        // We know:
        // r = 5e18
        // q0 = 5e18
        // qm = 2.5e18
        // k = 210721031315652584
        // T = 2 (day)
        // P = 9e18
        // Q(T) = (5e18 * ((5e18 - 2.5e18)/1e18) * (e^((210721031315652584 * 9e18)/5e18) - 1e18)) / (210721031315652584 * e^(210721031315652584 * 2))
        // Q(T) = -87.3670147008

        // Expect underflow
        vm.expectRevert("arithmetic overflow/underflow");

        // Calculate the price
        _module.priceFor(_lotId, payout);

        // TODO figure out why this is 35904284639349961078
    }
}
