// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "../../../../src/modules/Modules.sol";
import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";
import {IGradualDutchAuction} from
    "../../../../src/interfaces/modules/auctions/IGradualDutchAuction.sol";

import {UD60x18, ud, convert, UNIT, uUNIT, EXP_MAX_INPUT} from "prb-math-4.0-axis/UD60x18.sol";
import "prb-math-4.0-axis/Common.sol" as PRBMath;

import {GdaTest} from "./GDATest.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";

contract GdaCreateAuctionTest is GdaTest {
    using {PRBMath.mulDiv} for uint256;
    // [X] when the caller is not the parent
    //  [X] it reverts
    // [X] when the start time is in the past
    //  [X] it reverts
    // [X] when the duration is less than the globally configured minimum
    //  [X] it reverts
    // [X] when the equilibrium price is less than 10^(quotetoken decimals / 2)
    //  [X] it reverts
    // [X] when the equilibrium price is greater than the max uint128 value
    //  [X] it reverts
    // [X] when the minimum price is greater than 10% of equilibrium price less than the decay target price
    //  [X] it reverts
    // [X] when the decay target is less than the minimum
    //  [X] it reverts
    // [X] when the decay target is greater than the maximum
    //  [X] it reverts
    // [X] when the decay period is less than the minimum
    //  [X] it reverts
    // [X] when the decay period is greater than the maximum
    //  [X] it reverts
    // [X] when the capacity is in quote token
    //  [X] it reverts
    // [X] when capacity is less than the duration (in seconds)
    //  [X] it reverts
    // [X] when capacity is greater than the max uint128 value
    //  [X] it reverts
    // [X] when min price is nonzero and duration is greater than the ln of the max exp input divided by the calculated decay constant
    //  [X] it reverts
    // [X] when min price is zero and duration is greater than the max exp input divided by the calculated decay constant
    //  [X] it reverts
    // [X] when the inputs are all valid
    //  [X] it stores the auction data
    // [X] when the token decimals differ
    //  [X] it handles the calculations correctly

    function test_notParent_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        // Call the function (without pranking to auction house)
        _module.auction(_lotId, _auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
    }

    function test_startTimeInPast_reverts()
        public
        givenStartTimestamp(uint48(block.timestamp - 1))
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            IAuction.Auction_InvalidStart.selector, _auctionParams.start, uint48(block.timestamp)
        );
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_durationLessThanMinimum_reverts() public givenDuration(uint48(1 hours) - 1) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            IAuction.Auction_InvalidDuration.selector, _auctionParams.duration, uint48(1 hours)
        );
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_equilibriumPriceIsLessThanMin_reverts(
        uint128 price_
    ) public givenEquilibriumPrice(price_ % 1e9) {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 0);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_equilibriumPriceGreaterThanMax_reverts(
        uint256 price_
    ) public {
        vm.assume(price_ > type(uint128).max);
        _gdaParams.equilibriumPrice = price_;
        _auctionParams.implParams = abi.encode(_gdaParams);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 0);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_capacityInQuote_reverts() public givenCapacityInQuote {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 1);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_capacityLessThanMin_reverts(
        uint128 capacity_
    ) public givenLotCapacity(capacity_ % 1e9) {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 1);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_capacityGreaterThanMax_reverts(
        uint256 capacity_
    ) public {
        vm.assume(capacity_ > type(uint128).max);
        _auctionParams.capacity = capacity_;

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 1);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: capacity within bounds

    function test_minPriceGreaterThanDecayTargetPrice_reverts()
        public
        givenMinPrice(4e18)
        givenDecayTarget(25e16) // 25% decay from 5e18 is 3.75e18
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 4);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_minPriceEqualToDecayTargetPrice_reverts()
        public
        givenMinPrice(4e18)
        givenDecayTarget(20e16) // 20% decay from 5e18 is 4e18
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 4);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: min price within bounds of decay target

    function test_minPriceGreaterThanMax_reverts()
        public
        givenDecayTarget(20e16) // 20% decay from 5e18 is 4e18
        givenMinPrice(35e17 + 1) // 30% decrease (10% more than decay) from 5e18 is 3.5e18, we go slightly higher
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 4);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: min price within bounds of equilibrium price

    function test_decayTargetLessThanMinimum_reverts()
        public
        givenDecayTarget(1e16 - 1) // slightly less than 1%
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 2);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_decayTargetGreaterThanMaximum_reverts()
        public
        givenDecayTarget(40e16 + 1) // slightly more than 40%
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 2);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: decay target within bounds

    function test_decayPeriodLessThanMinimum_reverts()
        public
        givenDecayPeriod(uint48(6 hours) - 1)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 3);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_decayPeriodGreaterThanMaximum_reverts()
        public
        givenDecayPeriod(uint48(1 weeks) + 1)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 3);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: decay period within bounds

    function testFuzz_minPriceNonZero_durationGreaterThanLimit_reverts(
        uint8 decayTarget_,
        uint8 decayHours_
    ) public {
        // Normalize the inputs
        uint256 decayTarget = uint256(decayTarget_ % 40 == 0 ? 40 : decayTarget_ % 40) * 1e16;
        uint256 decayPeriod = uint256(decayHours_ % 163) * 1 hours + 6 hours;
        console2.log("Decay target:", decayTarget);
        console2.log("Decay period:", decayPeriod);

        // Calculate the decay constant
        // q1 > qm here because qm = 0.5 * q0, and the max decay target is 0.4
        uint256 quoteTokenScale = 10 ** _quoteTokenDecimals;
        UD60x18 q0 = ud(_gdaParams.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale));
        UD60x18 q1 = q0.mul(UNIT - ud(decayTarget)).div(UNIT);
        UD60x18 qm = ud(_gdaParams.minimumPrice.mulDiv(uUNIT, quoteTokenScale));

        console2.log("q0:", q0.unwrap());
        console2.log("q1:", q1.unwrap());
        console2.log("qm:", qm.unwrap());

        // Calculate the decay constant
        UD60x18 decayConstant = (q0 - qm).div(q1 - qm).ln().div(convert(decayPeriod).div(_ONE_DAY));
        console2.log("Decay constant:", decayConstant.unwrap());

        // Calculate the maximum duration in seconds
        uint256 maxDuration = convert(EXP_MAX_INPUT.div(decayConstant).mul(_ONE_DAY));
        console2.log("Max duration:", maxDuration);

        // Set the decay target and decay period to the fuzzed values
        // Set duration to the max duration plus 1
        _gdaParams.decayTarget = decayTarget;
        _gdaParams.decayPeriod = decayPeriod;
        _auctionParams.implParams = abi.encode(_gdaParams);
        _auctionParams.duration = uint48(maxDuration + 1);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 6);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: min price zero, duration greater than log

    function testFuzz_minPriceNonZero_durationEqualToLimit_succeeds(
        uint8 decayTarget_,
        uint8 decayHours_
    ) public {
        // Normalize the inputs
        uint256 decayTarget = uint256(decayTarget_ % 40 == 0 ? 40 : decayTarget_ % 40) * 1e16;
        uint256 decayPeriod = uint256(decayHours_ % 163) * 1 hours + 6 hours;
        console2.log("Decay target:", decayTarget);
        console2.log("Decay period:", decayPeriod);

        // Calculate the decay constant
        // q1 > qm here because qm = 0.5 * q0, and the max decay target is 0.4
        uint256 quoteTokenScale = 10 ** _quoteTokenDecimals;
        UD60x18 q0 = ud(_gdaParams.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale));
        UD60x18 q1 = q0.mul(UNIT - ud(decayTarget)).div(UNIT);
        UD60x18 qm = ud(_gdaParams.minimumPrice.mulDiv(uUNIT, quoteTokenScale));

        console2.log("q0:", q0.unwrap());
        console2.log("q1:", q1.unwrap());
        console2.log("qm:", qm.unwrap());

        // Calculate the decay constant
        UD60x18 decayConstant = (q0 - qm).div(q1 - qm).ln().div(convert(decayPeriod).div(_ONE_DAY));
        console2.log("Decay constant:", decayConstant.unwrap());

        // Calculate the maximum duration in seconds
        uint256 maxDuration = convert(LN_OF_PRODUCT_LN_MAX.div(decayConstant).mul(_ONE_DAY));
        console2.log("Max duration:", maxDuration);

        // Set the decay target and decay period to the fuzzed values
        // Set duration to the max duration
        _gdaParams.decayTarget = decayTarget;
        _gdaParams.decayPeriod = decayPeriod;
        _auctionParams.implParams = abi.encode(_gdaParams);
        _auctionParams.duration = uint48(maxDuration);

        // Call the function
        _createAuctionLot();
    }

    function testFuzz_minPriceZero_durationGreaterThanLimit_reverts(
        uint8 decayTarget_,
        uint8 decayHours_
    ) public givenMinPrice(0) {
        // Normalize the inputs
        uint256 decayTarget = uint256(decayTarget_ % 40 == 0 ? 40 : decayTarget_ % 40) * 1e16;
        uint256 decayPeriod = uint256(decayHours_ % 163) * 1 hours + 6 hours;
        console2.log("Decay target:", decayTarget);
        console2.log("Decay period:", decayPeriod);

        // Calculate the decay constant
        // q1 > qm here because qm < q0 * 0.50, which is the max decay target
        uint256 quoteTokenScale = 10 ** _quoteTokenDecimals;
        UD60x18 q0 = ud(_gdaParams.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale));
        UD60x18 q1 = q0.mul(UNIT - ud(decayTarget)).div(UNIT);
        UD60x18 qm = ud(_gdaParams.minimumPrice.mulDiv(uUNIT, quoteTokenScale));

        console2.log("q0:", q0.unwrap());
        console2.log("q1:", q1.unwrap());
        console2.log("qm:", qm.unwrap());

        // Calculate the decay constant
        UD60x18 decayConstant = (q0 - qm).div(q1 - qm).ln().div(convert(decayPeriod).div(_ONE_DAY));
        console2.log("Decay constant:", decayConstant.unwrap());

        // Calculate the maximum duration in seconds
        uint256 maxDuration = convert(EXP_MAX_INPUT.div(decayConstant).mul(_ONE_DAY));
        console2.log("Max duration:", maxDuration);

        // Set the decay target and decay period to the fuzzed values
        // Set duration to the max duration plus 1
        _gdaParams.decayTarget = decayTarget;
        _gdaParams.decayPeriod = decayPeriod;
        _auctionParams.implParams = abi.encode(_gdaParams);
        _auctionParams.duration = uint48(maxDuration + 1);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 5);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: min price not zero, duration greater than exponent

    function testFuzz_minPriceZero_durationEqualToLimit_succeeds(
        uint8 decayTarget_,
        uint8 decayHours_
    ) public givenMinPrice(0) {
        // Normalize the inputs
        uint256 decayTarget = uint256(decayTarget_ % 40 == 0 ? 40 : decayTarget_ % 40) * 1e16;
        uint256 decayPeriod = uint256(decayHours_ % 163) * 1 hours + 6 hours;
        console2.log("Decay target:", decayTarget);
        console2.log("Decay period:", decayPeriod);

        // Calculate the decay constant
        uint256 quoteTokenScale = 10 ** _quoteTokenDecimals;
        UD60x18 q0 = ud(_gdaParams.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale));
        UD60x18 q1 = q0.mul(UNIT - ud(decayTarget)).div(UNIT);
        UD60x18 qm = ud(_gdaParams.minimumPrice.mulDiv(uUNIT, quoteTokenScale));

        console2.log("q0:", q0.unwrap());
        console2.log("q1:", q1.unwrap());
        console2.log("qm:", qm.unwrap());

        // Calculate the decay constant
        UD60x18 decayConstant = (q0 - qm).div(q1 - qm).ln().div(convert(decayPeriod).div(_ONE_DAY));
        console2.log("Decay constant:", decayConstant.unwrap());

        // Calculate the maximum duration in seconds
        uint256 maxDuration = convert(EXP_MAX_INPUT.div(decayConstant).mul(_ONE_DAY));
        console2.log("Max duration:", maxDuration);

        // Set the decay target and decay period to the fuzzed values
        // Set duration to the max duration
        _gdaParams.decayTarget = decayTarget;
        _gdaParams.decayPeriod = decayPeriod;
        _auctionParams.implParams = abi.encode(_gdaParams);
        _auctionParams.duration = uint48(maxDuration);

        // Call the function
        _createAuctionLot();
    }

    function test_minPriceZero_EqPriceTimesEmissionsZero_reverts()
        public
        givenMinPrice(0)
        givenLotCapacity(1e9) // Smallest value for capacity is 10^(baseDecimals / 2). We divide the by the duration to get the emissions rate during creation.
        givenEquilibriumPrice(1e9) // Smallest value for equilibrium price is 10^(quoteDecimals / 2)
    {
        // Should revert with the standard duration of 2 days, since:
        // 1e9 * (1e9 * 1e18 / 2e18) / 1e18
        // = 1e9 * 5e8 / 1e18
        // = 5e17 / 1e18 = 0.5 (which gets truncated to zero)

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 7);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: min price not zero, eq price times emissions zero

    function test_minPriceNonZero_MinPriceTimesEmissionsZero_reverts()
        public
        givenMinPrice(1e9) // Smallest value for min price is 10^(quoteDecimals / 2)
        givenEquilibriumPrice(2e9) // Must be no more than 2x the min price
        givenLotCapacity(1e9) // Smallest value for capacity is 10^(baseDecimals / 2). We divide the by the duration to get the emissions rate during creation.
    {
        // Should revert with the standard duration of 2 days, since:
        // 1e9 * (1e9 * 1e18 / 2e18) / 1e18
        // = 1e9 * 5e8 / 1e18
        // = 5e17 / 1e18 = 0.5 (which gets truncated to zero)

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(IGradualDutchAuction.GDA_InvalidParams.selector, 8);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    // TODO: min price zero, min price times emissions zero

    function _assertAuctionData() internal {
        // Calculate the decay constant from the input parameters
        uint256 quoteTokenScale = 10 ** _quoteTokenDecimals;
        UD60x18 q0 = ud(_gdaParams.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale));
        UD60x18 q1 = q0.mul(UNIT - ud(_gdaParams.decayTarget)).div(UNIT);
        UD60x18 qm = ud(_gdaParams.minimumPrice.mulDiv(uUNIT, quoteTokenScale));
        UD60x18 decayConstant =
            (q0 - qm).div(q1 - qm).ln().div(convert(_gdaParams.decayPeriod).div(_ONE_DAY));

        // Calculate the emissions rate
        UD60x18 duration = convert(uint256(_auctionParams.duration)).div(_ONE_DAY);
        UD60x18 emissionsRate =
            ud(_auctionParams.capacity.mulDiv(uUNIT, 10 ** _baseTokenDecimals)).div(duration);

        // Check the auction data
        IGradualDutchAuction.AuctionData memory auctionData = _getAuctionData(_lotId);
        assertEq(auctionData.equilibriumPrice, _gdaParams.equilibriumPrice);
        assertEq(auctionData.minimumPrice, _gdaParams.minimumPrice);
        assertEq(auctionData.lastAuctionStart, _auctionParams.start);
        assertEq(auctionData.decayConstant.unwrap(), decayConstant.unwrap());
        assertEq(auctionData.emissionsRate.unwrap(), emissionsRate.unwrap());
    }

    function test_allInputsValid_storesAuctionData() public {
        // Call the function
        _createAuctionLot();

        // Check the auction data
        _assertAuctionData();
    }

    function test_quoteTokensDecimalsSmaller() public givenQuoteTokenDecimals(9) {
        // Call the function
        _createAuctionLot();

        // Check the auction data
        _assertAuctionData();
    }

    function test_quoteTokensDecimalsLarger() public givenBaseTokenDecimals(9) {
        // Call the function
        _createAuctionLot();

        // Check the auction data
        _assertAuctionData();
    }
}
