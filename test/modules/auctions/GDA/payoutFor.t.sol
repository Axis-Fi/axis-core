// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IGradualDutchAuction} from "src/interfaces/modules/auctions/IGradualDutchAuction.sol";

import {UD60x18, ud, convert, UNIT, uUNIT, EXP_MAX_INPUT} from "lib/prb-math/src/UD60x18.sol";
import "lib/prb-math/src/Common.sol" as PRBMath;

import {GdaTest} from "test/modules/auctions/GDA/GDATest.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract GdaPayoutForTest is GdaTest {
    using {PRBMath.mulDiv} for uint256;

    // [X] when the lot ID is invalid
    //   [X] it reverts
    // [ ] when minimum price is zero
    //   [X] it calculates the payout correctly
    //   [ ] when last auction start is in the future
    //     [ ] it calculates the payout correctly
    //   [ ] when last auction start is in the past
    //     [ ] it calculates the payout correctly
    // [ ] when minimum price is greater than zero
    //   [ ] when the payout for the amount at the minimum price is greater than the capacity
    //     [ ] it reverts
    //   [X] it calculates the payout correctly
    //   [ ] when last auction start is in the future
    //     [ ] it calculates the payout correctly
    //   [ ] when last auction start is in the past
    //     [ ] it calculates the payout correctly
    // [X] when amount is zero
    //   [X] it returns zero
    // [X] when large, reasonable values are used
    //   [X] it does not overflow
    // TODO can we fuzz this better? maybe use some external calculations to compare the values?
    // Otherwise, we're just recreating the same calculations here and not really validating anything

    function testFuzz_lotIdInvalid_reverts(uint96 lotId_) public {
        // No lots have been created so all lots are invalid
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, lotId_);
        vm.expectRevert(err);
        _module.payoutFor(lotId_, 1e18);
    }

    // function test_payoutGreaterThanRemainingCapacity_reverts() public givenLotIsCreated {
    //     // Payout is greater than remaining capacity
    //     bytes memory err = abi.encodeWithSelector(IAuction.Auction_InsufficientCapacity.selector);
    //     vm.expectRevert(err);
    //     _module.priceFor(_lotId, _LOT_CAPACITY + 1);
    // }

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

    // function test_minPriceNonZero_lastAuctionStartInFuture() public givenLotIsCreated {
    //     // We don't start the auction so the lastAuctionStart is 1 second ahead of the current time.
    //     // 1 seconds worth of tokens should be slightly more than the initial price.
    //     uint256 payout = _LOT_CAPACITY / _DURATION; // 1 seconds worth of tokens
    //     console2.log("1 second of token emissions:", payout);

    //     uint256 price = _module.priceFor(_lotId, payout);
    //     console2.log("Price for payout at beginning:", price);

    //     uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
    //     console2.log("Expected price:", expectedPrice);

    //     assertGe(price, expectedPrice);
    // }

    // function test_minPriceNonZero_lastAuctionStartInPast() public givenLotIsCreated {
    //     vm.warp(_start + 1);
    //     //lastAuctionStart is 1 second behind the current time.
    //     // 1 seconds worth of tokens should be slightly less than the initial price.
    //     uint256 payout = _LOT_CAPACITY / _DURATION; // 1 seconds worth of tokens
    //     console2.log("1 second of token emissions:", payout);

    //     uint256 price = _module.priceFor(_lotId, payout);
    //     console2.log("Price for payout at beginning:", price);

    //     uint256 expectedPrice = _INITIAL_PRICE.mulDiv(payout, _BASE_SCALE);
    //     console2.log("Expected price:", expectedPrice);

    //     assertLe(price, expectedPrice);
    // }

    // function testFuzz_minPriceZero_noOverflows(uint256 payout_)
    //     public
    //     givenLotCapacity(1e75) // very large number, but not quite max (which overflows)
    //     givenMinPrice(0)
    //     givenLotIsCreated
    //     givenLotHasStarted
    // {
    //     vm.assume(payout_ <= _LOT_CAPACITY);

    //     _module.priceFor(_lotId, payout_);
    // }

    // function testFuzz_minPriceNonZero_noOverflows(uint256 payout_)
    //     public
    //     givenLotCapacity(1e75) // very large number, but not quite max (which overflows)
    //     givenLotIsCreated
    //     givenLotHasStarted
    // {
    //     vm.assume(payout_ <= _LOT_CAPACITY);

    //     _module.priceFor(_lotId, payout_);
    // }
}
