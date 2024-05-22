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

    // [ ] when the lot ID is invalid
    //   [ ] it reverts
    // [ ] when payout is greater than remaining capacity
    //   [ ] it reverts
    // [ ] when minimum price is zero
    //   [ ] it calculates the price correctly
    // [ ] when minimum price is greater than zero
    //   [ ] it calculates the price correctly
    // [ ] when payout is zero
    //   [ ] it returns zero
    //

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
}
