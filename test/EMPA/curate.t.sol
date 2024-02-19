// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {EmpaTest} from "test/EMPA/EMPATest.sol";
import {EncryptedMarginalPriceAuction, FeeManager} from "src/EMPA.sol";

contract EmpaCurateTest is EmpaTest {
    // ===== Modifiers ===== //

    modifier givenCuratorIsZero() {
        _routingParams.curator = address(0);
        _;
    }

    modifier givenLotHasStarted() {
        vm.warp(_auctionParams.start + 1);
        _;
    }

    modifier givenLotHasConcluded() {
        vm.warp(_auctionParams.start + _auctionParams.duration + 1);
        _;
    }

    modifier givenLotHasBeenCancelled() {
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
        _;
    }

    // ===== Tests ===== //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given no curator is set
    //  [X] it reverts
    // [X] when the caller is not the lot curator
    //  [X] it reverts
    // [X] given the lot is already curated
    //  [X] it reverts
    // [X] given the lot has ended
    //  [X] it reverts
    // [X] given the lot has been cancelled
    //  [X] it reverts
    // [X] given no curator fee is set
    //  [X] it reverts
    // [X] given the lot is prefunded
    //  [X] it succeeds - the payout token is transferred to the auction house
    // [X] given the lot has not started
    //  [X] it succeeds
    // [X] it succeeds

    function test_whenLotIdIsInvalid() public {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenNoCuratorIsSet_whenCalledByCurator()
        public
        givenCuratorIsZero
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.NotPermitted.selector, _CURATOR);
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenNoCuratorIsSet_whenCalledByOwner()
        public
        givenCuratorIsZero
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.NotPermitted.selector, _auctionOwner
        );
        vm.expectRevert(err);

        // Call
        vm.prank(_auctionOwner);
        _auctionHouse.curate(_lotId);
    }

    function test_alreadyCurated()
        public
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorFeeIsSet
        givenOwnerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenOwnerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenLotHasStarted
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Curate again
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenLotHasConcluded()
        public
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketNotActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenLotHasBeenCancelled()
        public
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasBeenCancelled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketNotActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
    }

    function test_givenCuratorFeeNotSet()
        public
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
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
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorFeeIsSet
        givenOwnerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenOwnerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.curator, _CURATOR);
        assertTrue(lotRouting.curated);
        assertEq(lotRouting.curatorFee, _curatorMaxPotentialFee);

        // Maximum curator fee is transferred to the auction house
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: _auctionOwner balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");
    }

    function test_afterStart()
        public
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenOwnerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenOwnerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Curate
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);

        // Verify
        EncryptedMarginalPriceAuction.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.curator, _CURATOR);
        assertTrue(lotRouting.curated);
        assertEq(lotRouting.curatorFee, _curatorMaxPotentialFee);

        // Maximum curator fee is transferred to the auction house
        assertEq(
            _baseToken.balanceOf(_auctionOwner), 0, "base token: _auctionOwner balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction house balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance mismatch");
    }
}
