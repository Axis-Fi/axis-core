// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AuctionHouse} from "src/bases/AuctionHouse.sol";

import {BatchAuctionHouseTest} from "test/BatchAuctionHouse/AuctionHouseTest.sol";

contract BatchCurateTest is BatchAuctionHouseTest {
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
    // [X] given the callback is set
    //   [X] given the callback has the send base tokens flag
    //     [X] when the callback does not send enough base tokens
    //       [X] it reverts
    //     [X] it succeeds
    //   [X] the base token is transferred from the seller
    // [X] it succeeds - the payout token is transferred to the auction house, it caches the curator fee

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
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
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
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
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
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
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
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
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
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
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
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // Curator fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + _curatorMaxPotentialFee, "funding");
    }

    function test_beforeStart_givenCuratorFeeChanged()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Cache the old fee
        uint256 curatorMaxPotentialFeeOld = _curatorMaxPotentialFee;

        // Change the curator fee
        _setCuratorFee(_CURATOR_FEE_PERCENT + 1);

        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // Curator fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + curatorMaxPotentialFeeOld,
            "base token: auction house"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + curatorMaxPotentialFeeOld, "funding");
    }

    function test_afterStart()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + _curatorMaxPotentialFee, "funding");
    }

    function test_afterStart_givenCuratorFeeChanged()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Warp to start
        _startLot();

        // Cache the old fee
        uint256 curatorMaxPotentialFeeOld = _curatorMaxPotentialFee;

        // Change the curator fee
        _setCuratorFee(_CURATOR_FEE_PERCENT + 1);

        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + curatorMaxPotentialFeeOld,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + curatorMaxPotentialFeeOld, "funding");
    }

    function test_afterStart_quoteTokenDecimalsLarger()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            lotRouting.funding,
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "funding"
        );
    }

    function test_afterStart_quoteTokenDecimalsSmaller()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_curatorMaxPotentialFee))
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            lotRouting.funding,
            _scaleBaseTokenAmount(_LOT_CAPACITY) + _scaleBaseTokenAmount(_curatorMaxPotentialFee),
            "funding"
        );
    }

    function test_curatorFeeNotSet()
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
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, 0);

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + 0,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + 0, "funding");
    }

    function test_givenCallbackIsSet()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCallbackIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

        // Maximum _CURATOR fee is transferred to the auction house
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + _curatorMaxPotentialFee, "funding");

        // Check callback
        assertEq(_callback.lotCurated(_lotId), true, "lotCurated");
    }

    function test_givenCallbackIsSet_givenSendBaseTokensFlag()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));

        // Verify
        AuctionHouse.FeeData memory curation = _getLotFees(_lotId);
        assertEq(curation.curator, _CURATOR, "curator");
        assertEq(curation.curated, true, "curated");
        assertEq(curation.curatorFee, _CURATOR_FEE_PERCENT, "curator fee");

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
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");

        // Check routing
        AuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, _LOT_CAPACITY + _curatorMaxPotentialFee, "funding");

        // Check callback
        assertEq(_callback.lotCurated(_lotId), true, "lotCurated");
    }

    function test_givenCallbackIsSet_givenSendBaseTokensFlag_invariantBreaks_reverts()
        public
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenCallbackHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenCallbackHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenOnCurateCallbackBreaksInvariant
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(AuctionHouse.InvalidCallback.selector);
        vm.expectRevert(err);

        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));
    }
}
