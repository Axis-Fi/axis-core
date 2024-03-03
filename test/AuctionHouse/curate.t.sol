// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auctioneer} from "src/bases/Auctioneer.sol";
import {FeeManager} from "src/bases/FeeManager.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract CurateTest is AuctionHouseTest {
    // ===== Modifiers ===== //

    modifier givenCuratorIsZero() {
        _routingParams.curator = address(0);
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
    //  [X] it reverts
    // [X] given the lot is prefunded
    //  [X] it succeeds - the payout token is transferred to the auction house
    // [X] given the lot has not started
    //  [X] it succeeds
    // [X] it succeeds
    // [ ] it caches the curator fee

    function test_whenLotIdIsInvalid() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenNoCuratorIsSet_whenCalledByCurator_reverts()
        public
        givenCuratorIsZero
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.NotPermitted.selector, _CURATOR);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenNoCuratorIsSet_whenCalledByOwner_reverts()
        public
        givenCuratorIsZero
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.NotPermitted.selector, _auctionOwner);
        vm.expectRevert(err);

        // Call
        vm.prank(_auctionOwner);
        _auctionHouse.curate(_lotId);
    }

    function test_alreadyCurated_reverts()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
        vm.expectRevert(err);

        // Curate again
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenLotHasConcluded_reverts()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenLotIsConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenLotHasBeenCancelled_reverts()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenLotIsCancelled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenCuratorFeeNotSet_reverts()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(FeeManager.InvalidFee.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_beforeStart()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        (address lotCurator, bool lotCurated) = _auctionHouse.lotCuration(_lotId);
        assertEq(lotCurator, _CURATOR);
        assertTrue(lotCurated);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_auctionOwner), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);
    }

    function test_afterStart()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        (address lotCurator, bool lotCurated) = _auctionHouse.lotCuration(_lotId);
        assertEq(lotCurator, _CURATOR);
        assertTrue(lotCurated);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_auctionOwner), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);
    }

    function test_givenAtomicAuctionRequiresPrefunding()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAtomicAuctionRequiresPrefunding
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenOwnerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenOwnerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        (address lotCurator, bool lotCurated) = _auctionHouse.lotCuration(_lotId);
        assertEq(lotCurator, _CURATOR);
        assertTrue(lotCurated);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: _auctionOwner balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");
    }

    function test_givenAtomicAuctionRequiresPrefunding_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenOwnerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenOwnerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAtomicAuctionRequiresPrefunding
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenOwnerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenOwnerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        (address lotCurator, bool lotCurated) = _auctionHouse.lotCuration(_lotId);
        assertEq(lotCurator, _CURATOR);
        assertTrue(lotCurated);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: _auctionOwner balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");
    }

    function test_givenAtomicAuctionRequiresPrefunding_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenOwnerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenOwnerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAtomicAuctionRequiresPrefunding
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenOwnerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenOwnerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        (address lotCurator, bool lotCurated) = _auctionHouse.lotCuration(_lotId);
        assertEq(lotCurator, _CURATOR);
        assertTrue(lotCurated);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: _auctionOwner balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");
    }
}
