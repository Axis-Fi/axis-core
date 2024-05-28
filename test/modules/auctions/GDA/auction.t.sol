// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {IGradualDutchAuction} from "src/interfaces/modules/auctions/IGradualDutchAuction.sol";

import {UD60x18, ud, convert, UNIT, uUNIT, EXP_MAX_INPUT} from "lib/prb-math/src/UD60x18.sol";
import "lib/prb-math/src/Common.sol" as PRBMath;

import {GdaTest} from "test/modules/auctions/GDA/GDATest.sol";
import {console2} from "lib/forge-std/src/console2.sol";

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
    // [X] when the minimum price is greater than or equal to the decay target price
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

    function test_equilibriumPriceIsLessThanMin_reverts(uint128 price_)
        public
        givenEquilibriumPrice(uint256(price_) % 1e9)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_equilibriumPriceGreaterThanMax_reverts(uint256 price_)
        public
        givenEquilibriumPrice(price_)
    {
        vm.assume(price_ > type(uint128).max);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_capacityLessThanDuration_reverts(uint256 capacity_)
        public
        givenLotCapacity(capacity_ % _DURATION)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_capacityGreaterThanMax_reverts(uint256 capacity_)
        public
        givenLotCapacity(capacity_)
    {
        vm.assume(capacity_ > type(uint128).max);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_minPriceGreaterThanDecayTargetPrice_reverts()
        public
        givenMinPrice(4e18)
        givenDecayTarget(25e16) // 25% decay from 5e18 is 3.75e18
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_decayTargetLessThanMinimum_reverts()
        public
        givenDecayTarget(1e16 - 1) // slightly less than 1%
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_decayTargetGreaterThanMaximum_reverts()
        public
        givenDecayTarget(49e16 + 1) // slightly more than 49%
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_decayPeriodLessThanMinimum_reverts()
        public
        givenDecayPeriod(uint48(1 hours) - 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_decayPeriodGreaterThanMaximum_reverts()
        public
        givenDecayPeriod(uint48(1 weeks) + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_capacityInQuote_reverts() public givenCapacityInQuote {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function testFuzz_durationGreaterThanMaxExpInputDividedByDecayConstant_reverts(
        uint8 decayTarget_,
        uint8 decayHours_
    ) public {
        // Normalize the inputs
        uint256 decayTarget = uint256(decayTarget_ % 49 == 0 ? 49 : decayTarget_ % 49) * 1e16;
        uint256 decayPeriod = uint256(decayHours_ % 168 == 0 ? 168 : decayHours_ % 168) * 1 hours;
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
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function testFuzz_minPriceNonZero_durationEqualLnMaxExpInputDividedByDecayConstant_succeeds(
        uint8 decayTarget_,
        uint8 decayHours_
    ) public {
        // Normalize the inputs
        uint256 decayTarget = uint256(decayTarget_ % 49 == 0 ? 49 : decayTarget_ % 49) * 1e16;
        uint256 decayPeriod = uint256(decayHours_ % 168 == 0 ? 168 : decayHours_ % 168) * 1 hours;
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
        uint256 maxDuration = convert(LN_OF_EXP_MAX_INPUT.div(decayConstant).mul(_ONE_DAY));
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

     function testFuzz_minPriceZero_durationEqualMaxExpInputDividedByDecayConstant_succeeds(
        uint8 decayTarget_,
        uint8 decayHours_
    ) public givenMinPrice(0)
    {
        // Normalize the inputs
        uint256 decayTarget = uint256(decayTarget_ % 49 == 0 ? 49 : decayTarget_ % 49) * 1e16;
        uint256 decayPeriod = uint256(decayHours_ % 168 == 0 ? 168 : decayHours_ % 168) * 1 hours;
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
        // Set duration to the max duration
        _gdaParams.decayTarget = decayTarget;
        _gdaParams.decayPeriod = decayPeriod;
        _auctionParams.implParams = abi.encode(_gdaParams);
        _auctionParams.duration = uint48(maxDuration);

        // Call the function
        _createAuctionLot();
    }

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
