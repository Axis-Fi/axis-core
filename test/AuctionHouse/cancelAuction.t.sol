// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Auctions
import {Auction} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract CancelAuctionTest is AuctionHouseTest {
    uint96 internal constant _PURCHASE_AMOUNT = 1e18;

    bytes internal _purchaseAuctionData = abi.encode("");

    // cancel
    // [X] reverts if not the owner
    // [X] reverts if lot is not active
    // [X] reverts if lot id is invalid
    // [X] reverts if the lot is already cancelled
    // [X] given the auction is not prefunded
    //  [X] it sets the lot to inactive on the AuctionModule

    function testReverts_whenNotAuctionOwner()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
    {
        bytes memory err = abi.encodeWithSelector(Auctioneer.NotPermitted.selector, address(this));
        vm.expectRevert(err);

        _auctionHouse.cancel(_lotId);
    }

    function testReverts_whenUnauthorized(address user_)
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
    {
        vm.assume(user_ != _auctionOwner);

        bytes memory err = abi.encodeWithSelector(Auctioneer.NotPermitted.selector, user_);
        vm.expectRevert(err);

        vm.prank(user_);
        _auctionHouse.cancel(_lotId);
    }

    function testReverts_whenLotIdInvalid() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
    }

    function testReverts_whenLotIsInactive()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotIsConcluded
    {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
    }

    function test_givenCancelled_reverts()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotIsCancelled
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
    }

    function test_success()
        external
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
    {
        assertTrue(_atomicAuctionModule.isLive(_lotId), "before cancellation: isLive mismatch");

        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Get lot data from the module
        (, uint48 lotConclusion,,,, uint256 lotCapacity,,) = _atomicAuctionModule.lotData(_lotId);
        assertEq(lotConclusion, uint48(block.timestamp));
        assertEq(lotCapacity, 0);

        assertFalse(_atomicAuctionModule.isLive(_lotId), "after cancellation: isLive mismatch");
    }

    // [X] given the auction is prefunded
    //  [X] it refunds the prefunded amount in payout tokens to the owner
    //  [X] given a purchase has been made
    //   [X] it refunds the remaining prefunded amount in payout tokens to the owner

    modifier givenLotIsPrefunded() {
        _atomicAuctionModule.setRequiredPrefunding(true);

        // Mint payout tokens to the owner
        _baseToken.mint(_auctionOwner, _LOT_CAPACITY);

        // Approve transfer to the auction house
        vm.prank(_auctionOwner);
        _baseToken.approve(address(_auctionHouse), _LOT_CAPACITY);
        _;
    }

    function test_prefunded()
        external
        givenLotIsPrefunded
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
    {
        // Check the owner's balance
        uint256 ownerBalance = _baseToken.balanceOf(_auctionOwner);

        // Cancel the lot
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Check the owner's balance
        assertEq(_baseToken.balanceOf(_auctionOwner), ownerBalance + _LOT_CAPACITY);
    }

    function test_prefunded_givenPurchase()
        external
        givenLotIsPrefunded
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_PURCHASE_AMOUNT)
        givenUserHasApprovedQuoteToken(_PURCHASE_AMOUNT)
        givenPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT, _purchaseAuctionData)
    {
        // Check the owner's balance
        uint256 ownerBalance = _baseToken.balanceOf(_auctionOwner);

        // Cancel the lot
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Check the owner's balance
        assertEq(
            _baseToken.balanceOf(_auctionOwner), ownerBalance + _LOT_CAPACITY - _PURCHASE_AMOUNT
        );
    }

    // [X] given the auction is prefunded
    //  [X] given a curator is set
    //   [X] given a curator has not yet approved
    //    [X] nothing happens
    //   [X] given there have been purchases
    //    [X] it refunds the remaining prefunded amount in payout tokens to the owner
    //   [X] it refunds the prefunded amount in payout tokens to the owner

    modifier givenAuctionOwnerHasCuratorFeeBalance() {
        uint256 lotCapacity = _catalogue.remainingCapacity(_lotId);

        _curatorMaxPotentialFee = uint96(lotCapacity) * _CURATOR_FEE_PERCENT / 1e5;

        // Mint
        _baseToken.mint(_auctionOwner, _curatorMaxPotentialFee);

        // Approve spending
        vm.prank(_auctionOwner);
        _baseToken.approve(address(_auctionHouse), _curatorMaxPotentialFee);
        _;
    }

    function test_prefunded_givenCuratorIsSet()
        external
        givenLotIsPrefunded
        givenCuratorIsSet
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenAuctionOwnerHasCuratorFeeBalance
        givenCuratorMaxFeeIsSet
    {
        // Balance before
        uint256 auctionOwnerBalanceBefore = _baseToken.balanceOf(_auctionOwner);
        assertEq(
            auctionOwnerBalanceBefore,
            _curatorMaxPotentialFee,
            "base token: balance mismatch for auction owner before"
        ); // Curator fee not moved

        // Cancel the lot
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Check the base token balances
        assertEq(
            _baseToken.balanceOf(_auctionOwner),
            _curatorMaxPotentialFee + _LOT_CAPACITY,
            "base token: balance mismatch for auction owner"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch for auction house"
        );

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, 0, "mismatch on prefunding");
    }

    function test_prefunded_givenCuratorHasApproved()
        external
        givenLotIsPrefunded
        givenCuratorIsSet
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenAuctionOwnerHasCuratorFeeBalance
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
    {
        // Balance before
        uint256 auctionOwnerBalanceBefore = _baseToken.balanceOf(_auctionOwner);
        assertEq(
            auctionOwnerBalanceBefore, 0, "base token: balance mismatch for auction owner before"
        );

        // Cancel the lot
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Check the owner's balance
        assertEq(
            _baseToken.balanceOf(_auctionOwner),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: auction owner balance mismatch"
        ); // Capacity and max curator fee is returned
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch for auction house"
        );

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, 0, "mismatch on prefunding");
    }

    function test_prefunded_givenPurchase_givenCuratorHasApproved()
        external
        givenLotIsPrefunded
        givenCuratorIsSet
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_PURCHASE_AMOUNT)
        givenUserHasApprovedQuoteToken(_PURCHASE_AMOUNT)
        givenPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT, _purchaseAuctionData)
        givenCuratorMaxFeeIsSet
        givenAuctionOwnerHasCuratorFeeBalance
        givenCuratorFeeIsSet
        givenCuratorHasApproved
    {
        // Balance before
        uint256 auctionOwnerBalanceBefore = _baseToken.balanceOf(_auctionOwner);
        assertEq(
            auctionOwnerBalanceBefore, 0, "base token: balance mismatch for auction owner before"
        );

        // No curator fee, since the purchase was before curator approval
        uint256 curatorFee = 0;

        // Cancel the lot
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Check the owner's balance
        assertEq(
            _baseToken.balanceOf(_auctionOwner),
            _LOT_CAPACITY - _PURCHASE_AMOUNT + _curatorMaxPotentialFee - curatorFee,
            "base token: auction owner balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch for auction house"
        );

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, 0, "mismatch on prefunding");
    }

    function test_prefunded_givenPurchase_givenCuratorHasApproved_givenPurchase()
        external
        givenLotIsPrefunded
        givenCuratorIsSet
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_PURCHASE_AMOUNT)
        givenUserHasApprovedQuoteToken(_PURCHASE_AMOUNT)
        givenPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT, _purchaseAuctionData)
        givenCuratorMaxFeeIsSet
        givenAuctionOwnerHasCuratorFeeBalance
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_PURCHASE_AMOUNT * 2)
        givenUserHasApprovedQuoteToken(_PURCHASE_AMOUNT * 2)
        givenPurchase(_PURCHASE_AMOUNT * 2, _PURCHASE_AMOUNT * 2, _purchaseAuctionData)
    {
        // Balance before
        uint256 auctionOwnerBalanceBefore = _baseToken.balanceOf(_auctionOwner);
        assertEq(
            auctionOwnerBalanceBefore, 0, "base token: balance mismatch for auction owner before"
        );

        // No curator fee, since the purchase was before curator approval
        uint256 curatorFee = _CURATOR_FEE_PERCENT * (_PURCHASE_AMOUNT * 2) / 1e5;

        // Cancel the lot
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Check the owner's balance
        assertEq(
            _baseToken.balanceOf(_auctionOwner),
            _LOT_CAPACITY - _PURCHASE_AMOUNT - (_PURCHASE_AMOUNT * 2) + _curatorMaxPotentialFee
                - curatorFee,
            "base token: auction owner balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch for auction house"
        );

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, 0, "mismatch on prefunding");
    }

    function test_prefunded_givenCuratorHasApproved_givenPurchase()
        external
        givenLotIsPrefunded
        givenCuratorIsSet
        whenAuctionTypeIsAtomic
        whenAtomicAuctionModuleIsInstalled
        givenLotIsCreated
        givenLotHasStarted
        givenAuctionOwnerHasCuratorFeeBalance
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_PURCHASE_AMOUNT)
        givenUserHasApprovedQuoteToken(_PURCHASE_AMOUNT)
        givenPurchase(_PURCHASE_AMOUNT, _PURCHASE_AMOUNT, _purchaseAuctionData)
    {
        // Balance before
        uint256 auctionOwnerBalanceBefore = _baseToken.balanceOf(_auctionOwner);
        assertEq(
            auctionOwnerBalanceBefore, 0, "base token: balance mismatch for auction owner before"
        );

        uint256 curatorFee = _CURATOR_FEE_PERCENT * _PURCHASE_AMOUNT / 1e5;

        // Cancel the lot
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Check the owner's balance
        assertEq(
            _baseToken.balanceOf(_auctionOwner),
            _LOT_CAPACITY - _PURCHASE_AMOUNT + _curatorMaxPotentialFee - curatorFee,
            "base token: auction owner balance mismatch"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch for auction house"
        );

        // Check prefunding amount
        (,,,,,,,,, uint256 lotPrefunding) = _auctionHouse.lotRouting(_lotId);
        assertEq(lotPrefunding, 0, "mismatch on prefunding");
    }
}
