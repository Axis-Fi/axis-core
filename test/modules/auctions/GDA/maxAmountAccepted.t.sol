// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {uUNIT} from "prb-math-4.0-axis/UD60x18.sol";
import "prb-math-4.0-axis/Common.sol" as PRBMath;

import {GdaTest} from "./GDATest.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";

contract GdaMaxAmountAcceptedTest is GdaTest {
    using {PRBMath.mulDiv} for uint256;
    // [X] when the lot ID is invalid
    //   [X] it reverts
    // [X] it returns the price for the remaining capacity of the lot

    function testFuzz_lotIdInvalid_reverts(
        uint96 lotId_
    ) public {
        // No lots have been created so all lots are invalid
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, lotId_);
        vm.expectRevert(err);
        _module.maxAmountAccepted(lotId_);
    }

    function testFuzz_maxAmountAccepted_minPriceNonZero_success(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenDuration(1 days)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }

    function testFuzz_maxAmountAccepted_minPriceNonZero_success_smallerQuoteDecimals(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenQuoteTokenDecimals(6)
        givenDuration(1 days)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }

    function testFuzz_maxAmountAccepted_minPriceNonZero_success_smallerBaseDecimals(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenBaseTokenDecimals(6)
        givenDuration(1 days)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }

    function testFuzz_maxAmountAccepted_minPriceNonZero_success_bothSmallerDecimals(
        uint96 capacity_,
        uint96 price_
    )
        public
        givenQuoteTokenDecimals(9)
        givenBaseTokenDecimals(9)
        givenDuration(1 days)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }

    function testFuzz_maxAmountAccepted_minPriceZero_success(
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
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }

    function testFuzz_maxAmountAccepted_minPriceNonZero_quoteDecimalsSmaller_success(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenDuration(1 days)
        givenQuoteTokenDecimals(6)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }

    function testFuzz_maxAmountAccepted_minPriceZero_quoteDecimalsSmaller_success(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenDuration(1 days)
        givenQuoteTokenDecimals(6)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinPrice(0)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }

    function testFuzz_maxAmountAccepted_minPriceNonZero_quoteDecimalsLarger_success(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenDuration(1 days)
        givenBaseTokenDecimals(6)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinIsHalfPrice(price_)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }

    function testFuzz_maxAmountAccepted_minPriceZero_quoteDecimalsLarger_success(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenDuration(1 days)
        givenBaseTokenDecimals(6)
        givenLotCapacity(capacity_)
        givenEquilibriumPrice(price_)
        givenMinPrice(0)
        validateCapacity
        validatePrice
        validatePriceTimesEmissionsRate
        givenLotIsCreated
    {
        uint256 maxAmountAccepted = _module.maxAmountAccepted(_lotId);
        uint256 expectedAmount = _module.priceFor(_lotId, capacity_);
        assertEq(expectedAmount, maxAmountAccepted);
    }
}
