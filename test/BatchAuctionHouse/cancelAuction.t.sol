// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Auctions
import {IAuction} from "../../src/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "../../src/interfaces/IAuctionHouse.sol";

import {BatchAuctionHouseTest} from "./AuctionHouseTest.sol";

contract BatchCancelAuctionTest is BatchAuctionHouseTest {
    // cancel
    // [X] reverts if not the seller
    // [X] reverts if lot id is invalid
    // [X] reverts if the lot is already cancelled
    // [X] given the callback is set
    //  [X] given the callback has the send base tokens flag
    //   [X] the refund is sent to the callback and the onCancel callback called
    //  [X] the refund is sent to the seller and the onCancel callback is called
    // [X] given a curator is set
    //  [X] given a curator has not yet approved
    //   [X] nothing happens
    //  [X] given a curator has approved
    //   [X] it transfers the prefunded capacity and curator payout
    // [X] it transfers the prefunded capacity

    function test_whenNotSeller_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        bytes memory err =
            abi.encodeWithSelector(IAuctionHouse.NotPermitted.selector, address(this));
        vm.expectRevert(err);

        _auctionHouse.cancel(_lotId, bytes(""));
    }

    function test_whenUnauthorized_reverts(address user_)
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
    {
        vm.assume(user_ != _SELLER);

        bytes memory err = abi.encodeWithSelector(IAuctionHouse.NotPermitted.selector, user_);
        vm.expectRevert(err);

        vm.prank(user_);
        _auctionHouse.cancel(_lotId, bytes(""));
    }

    function test_whenLotIdInvalid_reverts() external {
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));
    }

    function test_whenLotIsConcluded_reverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
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
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
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

    function test_success()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Check the seller's balance
        uint256 sellerBalance = _baseToken.balanceOf(_SELLER);

        // Cancel the lot
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Check the seller's balance
        assertEq(
            _baseToken.balanceOf(_SELLER),
            sellerBalance + _LOT_CAPACITY,
            "base token: seller balance mismatch"
        );

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");
    }

    function test_givenCallback()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Check the seller's balance
        uint256 sellerBalance = _baseToken.balanceOf(_SELLER);

        // Cancel the lot
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Check the seller's balance
        assertEq(
            _baseToken.balanceOf(_SELLER),
            sellerBalance + _LOT_CAPACITY,
            "base token: seller balance mismatch"
        );

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");

        // Check the callback
        assertEq(_callback.lotCancelled(_lotId), true, "callback: lotCancelled mismatch");
    }

    function test_givenCallback_givenSendBaseTokensFlag()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCallbackHasSendBaseTokensFlag
        givenCallbackIsSet
        givenCallbackHasBaseTokenBalance(_LOT_CAPACITY)
        givenCallbackHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Check the callback's balance
        uint256 sellerBalance = _baseToken.balanceOf(address(_callback));

        // Cancel the lot
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Check the callback's balance
        assertEq(
            _baseToken.balanceOf(address(_callback)),
            sellerBalance + _LOT_CAPACITY,
            "base token: seller balance mismatch"
        );
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller balance mismatch");

        // Check routing
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");

        // Check the callback
        assertEq(_callback.lotCancelled(_lotId), true, "callback: lotCancelled mismatch");
    }

    function test_givenCuratorIsSet()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
    {
        // Balance before
        uint256 sellerBalanceBefore = _baseToken.balanceOf(_SELLER);
        assertEq(
            sellerBalanceBefore,
            _curatorMaxPotentialFee,
            "base token: balance mismatch for seller before"
        ); // Curator fee not moved

        // Cancel the lot
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Check the base token balances
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _curatorMaxPotentialFee + _LOT_CAPACITY,
            "base token: balance mismatch for seller"
        );
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch for auction house"
        );

        // Check funding amount
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");
    }

    function test_givenCuratorHasApproved()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenCuratorIsSet
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
    {
        // Balance before
        uint256 sellerBalanceBefore = _baseToken.balanceOf(_SELLER);
        assertEq(sellerBalanceBefore, 0, "base token: balance mismatch for seller before");

        // Cancel the lot
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));

        // Check the seller's balance
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _LOT_CAPACITY + _curatorMaxPotentialFee,
            "base token: seller balance mismatch"
        ); // Capacity and max curator fee is returned
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            0,
            "base token: balance mismatch for auction house"
        );

        // Check funding amount
        IAuctionHouse.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(lotRouting.funding, 0, "mismatch on funding");
    }
}
