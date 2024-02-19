// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";

// Auctions
import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaCancelAuctionTest is EmpaTest {
    uint96 internal _curatorMaxPotentialFee;

    // cancel
    // [X] reverts if not the owner
    // [X] reverts if lot is not active
    // [X] reverts if lot id is invalid
    // [X] reverts if the lot is already cancelled
    // [X] given the auction is not prefunded
    //  [X] it sets the lot to inactive on the AuctionModule

    function testReverts_whenNotAuctionOwner()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.NotPermitted.selector, address(this)
        );
        vm.expectRevert(err);

        _auctionHouse.cancel(_lotId);
    }

    function testReverts_whenUnauthorized(address user_)
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        vm.assume(user_ != _auctionOwner);

        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.NotPermitted.selector, user_);
        vm.expectRevert(err);

        vm.prank(user_);
        _auctionHouse.cancel(_lotId);
    }

    function testReverts_whenLotIdInvalid() external {
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
    }

    function testReverts_givenLotHasStarted()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        // Warp to start
        vm.warp(_startTime);

        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketActive.selector, _lotId
        );
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
    }

    function testReverts_whenLotIsInactive()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        // Warp to conclusion
        vm.warp(_startTime + _duration + 1);

        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketNotActive.selector, _lotId
        );
        vm.expectRevert(err);

        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
    }

    function test_givenCancelled_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        // Cancel the lot
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketNotActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call the function
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
    }

    // [X] given the auction is prefunded
    //  [X] it refunds the prefunded amount in payout tokens to the owner
    //  [X] given a purchase has been made
    //   [X] it refunds the remaining prefunded amount in payout tokens to the owner

    function test_prefunded()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        // Check the owner's balance
        uint256 ownerBalance = _baseToken.balanceOf(_auctionOwner);

        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);

        // Get lot data from the module
        EncryptedMarginalPriceAuction.Lot memory lotData = _getLotData(_lotId);
        assertEq(lotData.conclusion, uint48(block.timestamp));
        assertEq(lotData.capacity, 0);
        assertEq(uint8(lotData.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Check the owner's balance
        assertEq(_baseToken.balanceOf(_auctionOwner), ownerBalance + _LOT_CAPACITY);
    }

    // [X] given the auction is prefunded
    //  [X] given a curator is set
    //   [X] given a curator has not yet approved
    //    [X] nothing happens
    //   [X] given there have been purchases
    //    [X] it refunds the remaining prefunded amount in payout tokens to the owner
    //   [X] it refunds the prefunded amount in payout tokens to the owner

    modifier givenAuctionOwnerHasCuratorFeeBalance() {
        _curatorMaxPotentialFee = _CURATOR_FEE * _LOT_CAPACITY / 1e5;

        // Mint
        _baseToken.mint(_auctionOwner, _curatorMaxPotentialFee);

        // Approve spending
        vm.prank(_auctionOwner);
        _baseToken.approve(address(_auctionHouse), _curatorMaxPotentialFee);
        _;
    }

    function test_prefunded_givenCuratorIsSet()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
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
    }

    function test_prefunded_givenCuratorHasApproved()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenLotIsCreated
        givenAuctionOwnerHasCuratorFeeBalance
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
    }
}
