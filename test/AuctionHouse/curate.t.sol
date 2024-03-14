// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract CurateTest is AuctionHouseTest {
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
    // [X] given the lot is prefunded
    //  [X] given the callback is set
    //    [X] given the callback has the send base tokens flag
    //      [X] when the callback does not send enough base tokens
    //        [X] it reverts
    //      [X] it succeeds
    //    [X] the base token is transferred from the seller
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
        _auctionHouse.curate(_lotId, bytes(""));
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
        bytes memory err = abi.encodeWithSelector(Auctioneer.NotPermitted.selector, _SELLER);
        vm.expectRevert(err);

        // Call
        vm.prank(_SELLER);
        _auctionHouse.curate(_lotId, bytes(""));
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
        _auctionHouse.curate(_lotId, bytes(""));
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
        _auctionHouse.curate(_lotId, bytes(""));
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
        _auctionHouse.curate(_lotId, bytes(""));
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
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
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
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, 0);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
    }

    function test_beforeStart_givenCallbackIsSet()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackIsSet
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");

        // Check callback
        assertEq(_callback.lotCurated(_lotId), true, "lotCurated");
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
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // No _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0);
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0);
        assertEq(_baseToken.balanceOf(_CURATOR), 0);

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "funding");
    }

    function test_givenAuctionIsPrefunded()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionIsPrefunded
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + _curatorMaxPotentialFee, "funding");
    }

    function test_givenAuctionIsPrefunded_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAuctionIsPrefunded
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            lotRouting.funding,
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "funding"
        );
    }

    function test_givenAuctionIsPrefunded_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenAuctionIsPrefunded
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            lotRouting.funding,
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "funding"
        );
    }

    function test_givenAuctionIsPrefunded_curatorFeeNotSet()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionIsPrefunded
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, 0);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + 0,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + 0, "funding");
    }

    function test_givenAuctionIsPrefunded_givenCallbackIsSet()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionIsPrefunded
        givenCallbackIsSet
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + _curatorMaxPotentialFee, "funding");

        // Check callback
        assertEq(_callback.lotCurated(_lotId), true, "lotCurated");
    }

    function test_givenAuctionIsPrefunded_givenCallbackIsSet_givenSendBaseTokensFlag()
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAuctionIsPrefunded
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        Auctioneer.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR);
        assertEq(curation.curated, true);
        assertEq(curation.curatorFee, _curatorFeePercentActual);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(
            _baseToken.balanceOf(address(_callback)), 0, "base token: callback balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: _CURATOR balance mismatch");

        // Check routing
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + _curatorMaxPotentialFee, "funding");

        // Check callback
        assertEq(_callback.lotCurated(_lotId), true, "lotCurated");
    }

    function test_givenAuctionIsPrefunded_givenCallbackIsSet_givenSendBaseTokensFlag_invariantBreaks_reverts(
    )
        public
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenAuctionIsPrefunded
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenOnCurateCallbackBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidCallback.selector);
        vm.expectRevert(err);

        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));
    }
}
