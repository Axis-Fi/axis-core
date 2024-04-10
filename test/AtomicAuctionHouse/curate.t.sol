// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AuctionHouse} from "src/bases/AuctionHouse.sol";

import {AtomicAuctionHouseTest} from "test/AtomicAuctionHouse/AuctionHouseTest.sol";

contract AtomicCurateTest is AtomicAuctionHouseTest {
    // ===== Modifiers ===== //

    modifier givenCuratorIsZero() {
        _routingParams.curator = address(0);
        _;
    }

    modifier givenOnCurateCallbackBreaksInvariant() {
        _callback.setOnCurateMultiplier(9000);
        _;
    }

    // ===== Tests ===== //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given no _CURATOR is set
    //  [X] it reverts
    // [X] when the caller is not the lot _CURATOR
    //  [X] it reverts
    // [X] given the lot is already curated
    //  [X] it reverts
    // [X] given the lot has ended
    //  [X] it reverts
    // [X] given the lot has been cancelled
    //  [X] it reverts
    // [X] given no _CURATOR fee is set
    //  [X] it succeeds
    // [X] given the lot has not started
    //  [X] it succeeds
    // [X] it succeeds and it caches the curator fee

    function test_whenLotIdIsInvalid() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));
    }

    function test_givenNoCuratorIsSet_whenCalledByCurator_reverts()
        public
        givenCuratorIsZero
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.NotPermitted.selector, _CURATOR);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));
    }

    function test_givenNoCuratorIsSet_whenCalledBySeller_reverts()
        public
        givenCuratorIsZero
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.NotPermitted.selector, _SELLER);
        vm.expectRevert(err);

        // Call
        vm.prank(_SELLER);
        _auctionHouse.curate(_lotId, bytes(""));
    }

    function test_alreadyCurated_reverts()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidState.selector);
        vm.expectRevert(err);

        // Curate again
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));
    }

    function test_givenLotHasConcluded_reverts()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenLotIsCreated
        givenLotIsConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidState.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));
    }

    function test_givenLotHasBeenCancelled_reverts()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenLotIsCreated
        givenLotIsCancelled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidState.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));
    }

    function test_beforeStart()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
    }

    function test_beforeStart_curatorFeeNotSet()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenLotIsCreated
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, 0);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
    }

    function test_beforeStart_givenCallbackIsSet()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");

        // Check callback
        assertEq(_callback.lotCurated(_lotId), true, "lotCurated");
    }

    function test_afterStart()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
    }
}
