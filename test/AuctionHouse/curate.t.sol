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
    //  [X] it succeeds
    // [X] given the lot is prefunded
    //  [X] it succeeds - the payout token is transferred to the auction house
    // [X] given the lot has not started
    //  [X] it succeeds
    // [X] it succeeds
    // [X] it caches the curator fee

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

    function test_givenNoCuratorIsSet_whenCalledBySeller_reverts()
        public
        givenCuratorIsZero
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.NotPermitted.selector, _SELLER);
        vm.expectRevert(err);

        // Call
        vm.prank(_SELLER);
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
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);
    }

    function test_beforeStart_curatorFeeNotSet()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, 0);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
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
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);
    }

    function test_whenBatchAuction()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: _SELLER balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");
    }

    function test_whenBatchAuction_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: _SELLER balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");
    }

    function test_whenBatchAuction_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: _SELLER balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");
    }

    function test_whenBatchAuction_curatorFeeNotSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, 0);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: _SELLER balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + 0,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");
    }
}
