// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {uUNIT} from "lib/prb-math/src/UD60x18.sol";
import "lib/prb-math/src/Common.sol" as PRBMath;

import {GdaTest} from "test/modules/auctions/GDA/GDATest.sol";

contract GdaMaxPayoutTest is GdaTest {
    using {PRBMath.mulDiv} for uint256;
    // [X] when the lot ID is invalid
    //   [X] it reverts
    // [X] it returns the remaining capacity of the lot

    function testFuzz_lotIdInvalid_reverts(uint96 lotId_) public {
        // No lots have been created so all lots are invalid
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_InvalidLotId.selector, lotId_);
        vm.expectRevert(err);
        _module.maxPayout(lotId_);
    }

    function testFuzz_maxPayout_success(
        uint128 capacity_,
        uint128 price_
    ) public givenLotCapacity(uint256(capacity_)) givenEquilibriumPrice(uint256(price_)) {
        vm.assume(capacity_ >= _DURATION);
        uint256 decayedPrice = uint256(price_).mulDiv(uUNIT - _gdaParams.decayTarget, uUNIT);
        vm.assume(decayedPrice > _gdaParams.minimumPrice); // must have room for decay
        _createAuctionLot();

        uint256 maxPayout = _module.maxPayout(_lotId);
        uint256 expectedMaxPayout = capacity_;
        assertEq(expectedMaxPayout, maxPayout);
    }

    function testFuzz_maxPayout_minPriceZero_success(
        uint128 capacity_,
        uint128 price_
    )
        public
        givenLotCapacity(uint256(capacity_))
        givenEquilibriumPrice(uint256(price_))
        givenMinPrice(0)
    {
        vm.assume(capacity_ >= _DURATION);
        vm.assume(price_ >= 1e3);
        _createAuctionLot();

        uint256 maxPayout = _module.maxPayout(_lotId);
        uint256 expectedMaxPayout = capacity_;
        assertEq(expectedMaxPayout, maxPayout);
    }
}
