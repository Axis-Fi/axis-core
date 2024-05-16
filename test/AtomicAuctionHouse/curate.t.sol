// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";

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
    // [X] given No curator fee is set
    //  [X] it succeeds
    // [X] given the lot has not started
    //  [X] it succeeds
    // [X] it succeeds and it caches the curator fee

    function test_whenLotIdIsInvalid() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, _lotId);
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
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.NotPermitted.selector, _CURATOR);
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
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.NotPermitted.selector, _SELLER);
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
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidState.selector);
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
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidState.selector);
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
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidState.selector);
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
        IAuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // No curator fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
    }

    function test_beforeStart_givenCuratorFeeChanged()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
    {
        // Change the curator fee
        _setCuratorFee(_CURATOR_FEE_PERCENT + 1);

        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        IAuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curatorFee"); // Original value from time of creation

        // No curator fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "auctionHouse");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "curator");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
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
        IAuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, 0);

        // No curator fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
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
        IAuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // No curator fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
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
        IAuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // No curator fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
    }

    function test_afterStart_givenCuratorFeeChanged()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
    {
        // Warp to start
        _startLot();

        // Change the curator fee
        _setCuratorFee(_CURATOR_FEE_PERCENT + 1);

        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        IAuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee"); // Does not change

        // No curator fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
    }
}
