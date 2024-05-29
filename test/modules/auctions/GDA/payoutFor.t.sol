// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IGradualDutchAuction} from "src/interfaces/modules/auctions/IGradualDutchAuction.sol";

import {
    UD60x18, ud, convert, UNIT, uUNIT, ZERO, EXP_MAX_INPUT
} from "lib/prb-math/src/UD60x18.sol";
import "lib/prb-math/src/Common.sol" as PRBMath;

import {GdaTest} from "test/modules/auctions/GDA/GDATest.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract GdaPayoutForTest is GdaTest {
    using {PRBMath.mulDiv} for uint256;

    // [X] when the lot ID is invalid
    //   [X] it reverts
    // [X] when the calculated payout is greater than the remaining capacity of the lot
    //   [X] it reverts
    // [X] when minimum price is zero
    //   [X] it calculates the payout correctly
    //   [X] when last auction start is in the future
    //     [X] it calculates the payout correctly
    //   [X] when last auction start is in the past
    //     [X] it calculates the payout correctly
    // [X] when minimum price is greater than zero
    //   [X] it calculates the payout correctly
    //   [X] when last auction start is in the future
    //     [X] it calculates the payout correctly
    //   [X] when last auction start is in the past
    //     [X] it calculates the payout correctly
    // [X] when amount is zero
    //   [X] it returns zero
    // [X] when large, reasonable values are used
    //   [X] it does not overflow
    // TODO can we fuzz this better?

    function testFuzz_lotIdInvalid_reverts(uint96 lotId_) public {
        // No lots have been created so all lots are invalid
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, lotId_);
        vm.expectRevert(err);
        _module.payoutFor(lotId_, 1e18);
    }

    function test_amountGreaterThanMaxAccepted_reverts()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 maxAccepted = _module.maxAmountAccepted(_lotId);

        // Payout is greater than remaining capacity
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InsufficientCapacity.selector);
        vm.expectRevert(err);

        _module.payoutFor(_lotId, maxAccepted + 100_000); // TODO due to precision issues, it must be somewhat over the max amount accepted to revert
    }

    function test_minPriceZero_payoutZeroForAmountZero()
        public
        givenMinPrice(0)
        givenLotIsCreated
    {
        uint256 amount = 0;
        uint256 payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout for 0 amount:", payout);
        assertEq(payout, 0);
    }

    function test_minPriceNonZero_payoutZeroForAmountZero()
        public
        givenLotIsCreated
        givenLotHasStarted
    {
        uint256 amount = 0;
        uint256 payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout for 0 amount:", payout);
        assertEq(payout, 0);
    }

    function test_minPriceZero() public givenMinPrice(0) givenLotIsCreated givenLotHasStarted {
        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 amount = _INITIAL_PRICE.mulDiv(_LOT_CAPACITY / _DURATION, _BASE_SCALE); // 1 seconds worth of tokens
        console2.log("amount equivalent to 1 second of token emissions:", amount);

        uint256 payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout at start:", payout);

        uint256 expectedPayout = amount.mulDiv(_BASE_SCALE, _INITIAL_PRICE);
        console2.log("Expected payout at start:", expectedPayout);

        // The payout should be conservative (less than or equal to the expected payout)
        assertApproxEqRel(payout, expectedPayout, 1e14); // 0.01%
        assertLe(payout, expectedPayout);

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD);
        // The first auction has concluded. The price should be the target price for the decay period.
        uint256 decayedPrice = _INITIAL_PRICE.mulDiv(1e18 - _DECAY_TARGET, 1e18);
        amount = decayedPrice.mulDiv(_LOT_CAPACITY / _DURATION, _BASE_SCALE);
        payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout at end of decay period:", payout);

        expectedPayout = amount.mulDiv(_BASE_SCALE, decayedPrice);
        console2.log("Expected payout at end of decay period:", expectedPayout);

        // The payout should be conservative (less than or equal to the expected payout)
        assertApproxEqRel(payout, expectedPayout, 1e14); // 0.01%
        assertLe(payout, expectedPayout);
    }

    function test_minPriceZero_lastAuctionStartInFuture()
        public
        givenMinPrice(0)
        givenLotIsCreated
    {
        // We don't start the auction so the lastAuctionStart is 1 second ahead of the current time.
        // Payout should be slightly less than 1 seconds worth of tokens
        uint256 amount = _INITIAL_PRICE.mulDiv(_LOT_CAPACITY / _DURATION, _BASE_SCALE); // 1 seconds worth of tokens
        console2.log("amount equivalent to 1 second of token emissions:", amount);

        uint256 payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout:", payout);

        uint256 expectedPayout = amount.mulDiv(_BASE_SCALE, _INITIAL_PRICE);
        console2.log("Expected payout:", expectedPayout);

        assertLe(payout, expectedPayout);
    }

    function test_minPriceZero_lastAuctionStartInPast() public givenMinPrice(0) givenLotIsCreated {
        vm.warp(_start + 1);
        //lastAuctionStart is 1 second behind the current time.
        // Payout should be slightly more than 1 seconds worth of tokens
        uint256 amount = _INITIAL_PRICE.mulDiv(_LOT_CAPACITY / _DURATION, _BASE_SCALE); // 1 seconds worth of tokens
        console2.log("amount equivalent to 1 second of token emissions:", amount);

        uint256 payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout:", payout);

        uint256 expectedPayout = amount.mulDiv(_BASE_SCALE, _INITIAL_PRICE);
        console2.log("Expected payout:", expectedPayout);

        assertGe(payout, expectedPayout);
    }

    function test_minPriceNonZero() public givenLotIsCreated givenLotHasStarted {
        // The timestamp is the start time so current time == last auction start.
        // The first auction is now starting. 1 seconds worth of tokens should be at the initial price.
        uint256 amount = _INITIAL_PRICE.mulDiv(_LOT_CAPACITY / _DURATION, _BASE_SCALE); // 1 seconds worth of tokens
        console2.log("amount equivalent to 1 second of token emissions:", amount);

        uint256 payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout at start:", payout);

        uint256 expectedPayout = amount.mulDiv(_BASE_SCALE, _INITIAL_PRICE);
        console2.log("Expected payout at start:", expectedPayout);

        // The payout should be conservative (less than or equal to the expected payout)
        assertApproxEqRel(payout, expectedPayout, 1e14); // 0.01%
        assertLe(payout, expectedPayout);

        // Warp to the end of the decay period
        vm.warp(_start + _DECAY_PERIOD);
        // The first auction has concluded. The price should be the target price for the decay period.
        uint256 decayedPrice = _INITIAL_PRICE.mulDiv(1e18 - _DECAY_TARGET, 1e18);
        amount = decayedPrice.mulDiv(_LOT_CAPACITY / _DURATION, _BASE_SCALE);
        payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout at end of decay period:", payout);

        expectedPayout = amount.mulDiv(_BASE_SCALE, decayedPrice);
        console2.log("Expected payout at end of decay period:", expectedPayout);

        // The payout should be conservative (less than or equal to the expected payout)
        assertApproxEqRel(payout, expectedPayout, 1e14); // 0.01%
        assertLe(payout, expectedPayout);
    }

    function test_minPriceNonZero_lastAuctionStartInFuture() public givenLotIsCreated {
        // We don't start the auction so the lastAuctionStart is 1 second ahead of the current time.
        // Payout should be slightly less than 1 seconds worth of tokens
        uint256 amount = _INITIAL_PRICE.mulDiv(_LOT_CAPACITY / _DURATION, _BASE_SCALE); // 1 seconds worth of tokens
        console2.log("amount equivalent to 1 second of token emissions:", amount);

        uint256 payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout:", payout);

        uint256 expectedPayout = amount.mulDiv(_BASE_SCALE, _INITIAL_PRICE);
        console2.log("Expected payout:", expectedPayout);

        assertLe(payout, expectedPayout);
    }

    function test_minPriceNonZero_lastAuctionStartInPast() public givenLotIsCreated {
        vm.warp(_start + 1);
        //lastAuctionStart is 1 second behind the current time.
        // Payout should be slightly more than 1 seconds worth of tokens
        uint256 amount = _INITIAL_PRICE.mulDiv(_LOT_CAPACITY / _DURATION, _BASE_SCALE); // 1 seconds worth of tokens
        console2.log("amount equivalent to 1 second of token emissions:", amount);

        uint256 payout = _module.payoutFor(_lotId, amount);
        console2.log("Payout:", payout);

        uint256 expectedPayout = amount.mulDiv(_BASE_SCALE, _INITIAL_PRICE);
        console2.log("Expected payout:", expectedPayout);

        assertGe(payout, expectedPayout);
    }

    function testFuzz_minPriceZero_noOverflows(
        uint128 capacity_,
        uint128 amount_
    )
        public
        givenLotCapacity(capacity_)
        givenMinPrice(0)
        validateCapacity
        givenLotIsCreated
        givenLotHasStarted
    {
        vm.assume(amount_ <= _module.maxAmountAccepted(_lotId));

        _module.payoutFor(_lotId, amount_);
    }

    function testFuzz_minPriceNonZero_noOverflows(
        uint128 capacity_,
        uint128 amount_
    ) public givenLotCapacity(capacity_) validateCapacity givenLotIsCreated givenLotHasStarted {
        vm.assume(amount_ <= _module.maxAmountAccepted(_lotId));

        _module.payoutFor(_lotId, amount_);
    }

    function testFuzz_minPriceZero_varyingSetup(
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

        uint256 expectedPayout = _auctionParams.capacity / _DURATION;
        uint256 amount = _gdaParams.equilibriumPrice.mulDiv(expectedPayout, _BASE_SCALE);
        console2.log("Amount:", amount);
        uint256 payout = _module.payoutFor(_lotId, amount);
        assertLe(payout, expectedPayout);
        // assertApproxEqRel(payout, expectedPayout, 1e16); //TODO how to think about these bounds? some extremes have large errors

        vm.warp(_start + _DECAY_PERIOD);
        amount = _gdaParams.equilibriumPrice.mulDiv(uUNIT - _gdaParams.decayTarget, uUNIT).mulDiv(
            expectedPayout, _BASE_SCALE
        );
        payout = _module.payoutFor(_lotId, amount);
        assertLe(payout, expectedPayout);
        // assertApproxEqRel(payout, expectedPayout, 1e16);
    }

    function testFuzz_minPriceNonZero_varyingSetup(
        uint128 capacity_,
        uint128 price_,
        uint128 minPrice_
    )
        public
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinPrice(minPrice_)
        validateCapacity
        validatePrice
        validateMinPrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
        givenLotHasStarted
    {
        console2.log("Capacity:", capacity_);
        console2.log("Price:", price_);

        uint256 expectedPayout = _auctionParams.capacity / _auctionParams.duration;
        uint256 amount = _gdaParams.equilibriumPrice.mulDiv(expectedPayout, _BASE_SCALE);
        console2.log("Amount:", amount);
        uint256 payout = _module.payoutFor(_lotId, amount);
        assertLe(payout, expectedPayout);
        // assertApproxEqRel(payout, expectedPayout, 1e16); //TODO how to think about these bounds? some extremes have large errors

        vm.warp(_start + _auctionParams.duration);
        amount = _gdaParams.equilibriumPrice.mulDiv(uUNIT - _gdaParams.decayTarget, uUNIT).mulDiv(
            expectedPayout, _BASE_SCALE
        );
        payout = _module.payoutFor(_lotId, amount);
        assertLe(payout, expectedPayout);
        // assertApproxEqRel(payout, expectedPayout, 1e16);
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

        // Set amount to 1 seconds worth of tokens (which is qt divided by 1 day)
        uint256 amount = qt.intoUint256().mulDiv(10 ** _quoteTokenDecimals, uUNIT) / 1 days;

        // Calculate the payout
        uint256 payout = _module.payoutFor(_lotId, amount);

        // Calculate the expected payout
        uint256 expectedPayout = _LOT_CAPACITY / _DURATION;

        // The payout should be conservative (less than or equal to the expected payout)
        assertLe(payout, expectedPayout);
        assertApproxEqRel(payout, expectedPayout, 1e14); // 0.01%
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

        // Set amount to 1 seconds worth of tokens (which is qt divided by 1 day)
        uint256 amount = qt.intoUint256().mulDiv(10 ** _quoteTokenDecimals, uUNIT) / 1 days;

        // Calculate the payout
        uint256 payout = _module.payoutFor(_lotId, amount);

        // Calculate the expected payout
        uint256 expectedPayout = _LOT_CAPACITY / _DURATION;

        // The payout should be conservative (less than or equal to the expected payout)
        assertLe(payout, expectedPayout);
        assertApproxEqRel(payout, expectedPayout, 1e14); // 0.01%
    }
}
