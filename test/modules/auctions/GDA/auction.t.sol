// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Module} from "src/modules/Modules.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
// import {GradualDutchAuction} from "src/modules/auctions/GDA.sol";

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
    // [X] when the equilibrium price is 0
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
    // [ ] when duration is greater than the max exp input divided by the calculated decay constant
    //  [ ] it reverts
    // [ ] when the inputs are all valid
    //  [ ] it stores the auction data
    // [ ] when the token decimals differ
    //  [ ] it handles the calculations correctly

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

    function test_equilibriumPriceIsZero_reverts() public givenEquilibriumPrice(0) {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }

    function test_minPriceGreaterThanDecayTargePrice_reverts()
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

    function test_minPriceEqualToDecayTargePrice_reverts()
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
        givenDecayTarget(50e16 + 1) // slightly more than 50%
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

    function testFuzz_durationGreaterThanMaxExpInputDividedByDecayConstant_reverts(uint8 decayTarget_, uint8 decayHours_) public {
        // Normalize the inputs
        uint256 decayTarget = uint256(decayTarget_ % 50 == 0 ? 50 : decayTarget_ % 50) * 1e16;
        uint256 decayPeriod = uint256(decayHours_ % 168 == 0 ? 168 : decayHours_ % 168) * 1 hours;

        // Calculate the decay constant
        // q1 > qm here because qm < q0 * 0.50, which is the max decay target
        uint256 quoteTokenScale = 10 ** _quoteTokenDecimals;
        UD60x18 q0 = ud(_gdaParams.equilibriumPrice.mulDiv(uUNIT, quoteTokenScale));
        UD60x18 q1 = q0.mul(UNIT - ud(decayTarget)).div(UNIT);
        UD60x18 qm = ud(_gdaParams.minimumPrice.mulDiv(uUNIT, quoteTokenScale));

        // Calculate the decay constant
        UD60x18 decayConstant = (q0 - qm).div(q1 - qm).ln().div(convert(decayPeriod).div(_ONE_DAY));

        // Calculate the maximum duration in seconds
        uint256 maxDuration = convert(EXP_MAX_INPUT.div(decayConstant).mul(_ONE_DAY));
        console2.log("Max duration:", maxDuration);

        // Set the duration parameter to the max duration plus 1
        _auctionParams.duration = uint48(maxDuration + 1);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidParams.selector);
        vm.expectRevert(err);

        // Call the function
        _createAuctionLot();
    }
}
