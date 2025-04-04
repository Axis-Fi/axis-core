// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Auctions
import {IAuction} from "../../src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "../../src/interfaces/IAuctionHouse.sol";

import {AtomicAuctionHouseTest} from "./AuctionHouseTest.sol";

contract AtomicCancelAuctionTest is AtomicAuctionHouseTest {
    uint256 internal constant _PURCHASE_AMOUNT = 2e18;
    uint256 internal constant _PURCHASE_AMOUNT_OUT = 1e18;
    uint32 internal constant _PAYOUT_MULTIPLIER = 5000; // 50%

    bytes internal _purchaseAuctionData = abi.encode("");

    modifier givenPayoutMultiplier(
        uint256 multiplier_
    ) {
        _atomicAuctionModule.setPayoutMultiplier(_lotId, multiplier_);
        _;
    }

    // cancel
    // [X] reverts if not the seller
    // [X] reverts if lot id is invalid
    // [X] reverts if the lot is already cancelled
    // [X] given the auction is not prefunded
    //  [X] it sets the lot to inactive on the AuctionModule
    // [X] given the lot has not started
    //  [X] it succeeds
    // [X] given the curator has approved
    //  [X] it succeeds
    // [X] given there have been purchases
    //  [X] it succeeds
    // [X] given the callback is set
    //  [X] and the onCancel callback called

    function testReverts_whenNotSeller()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
    {
        bytes memory err =
            abi.encodeWithSelector(IAuctionHouse.NotPermitted.selector, address(this));
        vm.expectRevert(err);

        _auctionHouse.cancel(_lotId, bytes(""));
    }

    function testReverts_whenUnauthorized(
        address user_
    ) external whenAuctionTypeIsAtomic whenAtomicAuctionModuleIsInstalled givenLotIsCreated {
        vm.assume(user_ != _SELLER);

        bytes memory err = abi.encodeWithSelector(IAuctionHouse.NotPermitted.selector, user_);
        vm.expectRevert(err);

        vm.prank(user_);
        _auctionHouse.cancel(_lotId, bytes(""));
    }

    function testReverts_whenLotIdInvalid() external {
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));
    }

    function testReverts_whenLotIsConcluded()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotIsConcluded
    {
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));
    }

    function test_givenCancelled_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotIsCancelled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IAuction.Auction_LotNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));
    }

    function test_whenBeforeStart()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
    {
        // Cancel the lot
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Get lot data from the module
        IAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(lot.conclusion, uint48(block.timestamp));
        assertEq(lot.capacity, 0);

        assertFalse(_atomicAuctionModule.isLive(_lotId), "after cancellation: isLive mismatch");
    }

    function test_success()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
    {
        assertTrue(_atomicAuctionModule.isLive(_lotId), "before cancellation: isLive mismatch");

        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Get lot data from the module
        IAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(lot.conclusion, uint48(block.timestamp));
        assertEq(lot.capacity, 0);

        assertFalse(_atomicAuctionModule.isLive(_lotId), "after cancellation: isLive mismatch");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");
    }

    function test_givenCuratorIsSet()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenCuratorHasApproved
        givenLotHasStarted
    {
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Get lot data from the module
        IAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(lot.conclusion, uint48(block.timestamp));
        assertEq(lot.capacity, 0);

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");
    }

    function test_givenPurchase()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenUserHasQuoteTokenBalance(_PURCHASE_AMOUNT)
        givenUserHasQuoteTokenAllowance(_PURCHASE_AMOUNT)
        givenPayoutMultiplier(_PAYOUT_MULTIPLIER)
        givenPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT_OUT, _purchaseAuctionData)
    {
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Get lot data from the module
        IAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(lot.conclusion, uint48(block.timestamp));
        assertEq(lot.capacity, 0);

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");

        // Check balances
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _LOT_CAPACITY - _PURCHASE_AMOUNT_OUT,
            "seller: base token balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)), 0, "contract: base token balance mismatch"
        );
    }

    function test_givenCallback()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenCallbackIsSet
        givenLotIsCreated
        givenLotHasStarted
    {
        assertTrue(_atomicAuctionModule.isLive(_lotId), "before cancellation: isLive mismatch");

        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Get lot data from the module
        IAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(lot.conclusion, uint48(block.timestamp));
        assertEq(lot.capacity, 0);

        assertFalse(_atomicAuctionModule.isLive(_lotId), "after cancellation: isLive mismatch");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");

        // Check the callback
        assertEq(_callback.lotCancelled(_lotId), true, "callback: lotCancelled mismatch");
    }
}
