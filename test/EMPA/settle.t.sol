// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {EncryptedMarginalPriceAuction} from "src/EMPA.sol";

contract EmpaSettleTest is EmpaTest {
    uint96 internal constant _bidPriceOneAmount = 1e18;
    uint96 internal constant _bidPriceOneAmountOut = 1e18;
    uint96 internal constant _bidPriceHalfAmount = 1e18;
    uint96 internal constant _bidPriceHalfAmountOut = 2e18;
    uint96 internal constant _bidPriceTwoAmount = 2e18;
    uint96 internal constant _bidPriceTwoAmountOut = 1e18;
    uint96 internal constant _bidSizeBelowMinimumAmount = 1e15;
    uint96 internal constant _bidSizeBelowMinimumAmountOut = 1e16;
    uint96 internal constant _bidSizeNineAmount = 27e18;
    uint96 internal constant _bidSizeNineAmountOut = 9e18;
    uint96 internal constant _bidSizeTwoAmount = 4e18;
    uint96 internal constant _bidSizeTwoAmountOut = 2e18;

    // ============ Modifiers ============ //

    function _adjustQuoteTokenDecimals(uint96 amount_) internal view returns (uint96) {
        uint256 adjustedAmount = amount_ * 10 ** (_quoteToken.decimals()) / 1e18;

        if (adjustedAmount > type(uint96).max) revert("overflow");

        return uint96(adjustedAmount);
    }

    function _adjustBaseTokenDecimals(uint96 amount_) internal view returns (uint96) {
        uint256 adjustedAmount = amount_ * 10 ** (_baseToken.decimals()) / 1e18;

        if (adjustedAmount > type(uint96).max) revert("overflow");

        return uint96(adjustedAmount);
    }

    modifier givenBidsAreBelowMinimumFilled() {
        // Capacity: 1 + 1 < 2.5
        // Marginal price: 2 >= 2
        _createBid(_bidPriceTwoAmount, _bidPriceTwoAmountOut);
        _createBid(_bidPriceTwoAmount, _bidPriceTwoAmountOut);
        _;
    }

    modifier givenAllBidsAreBelowMinimumPrice() {
        // Capacity: 1 + 1 + 1 >= 2.5
        // Marginal price: 1 < 2
        _createBid(_bidPriceOneAmount, _bidPriceOneAmountOut);
        _createBid(_bidPriceOneAmount, _bidPriceOneAmountOut);
        _createBid(_bidPriceOneAmount, _bidPriceOneAmountOut);
        _;
    }

    modifier givenBidsAreAboveMinimumAndBelowCapacity() {
        // Capacity: 1 + 1 + 1 + 1 >= 2.5 && < 10
        // Marginal price: 2 >= 2
        _createBid(_bidPriceTwoAmount, _bidPriceTwoAmountOut);
        _createBid(_bidPriceTwoAmount, _bidPriceTwoAmountOut);
        _createBid(_bidPriceTwoAmount, _bidPriceTwoAmountOut);
        _createBid(_bidPriceTwoAmount, _bidPriceTwoAmountOut);
        _;
    }

    modifier givenBidsAreOverSubscribed() {
        // Capacity: 9 + 2 > 10
        // Marginal price: 2 >= 2
        _createBid(_bidSizeNineAmount, _bidSizeNineAmountOut);
        _createBid(_bidSizeTwoAmount, _bidSizeTwoAmountOut);
        _;
    }

    modifier givenSomeBidsAreBelowMinimumPrice() {
        // Capacity: 2 + 2 + 1 + 1 >= 2.5
        // Marginal price: 2 >= 2
        _createBid(_bidSizeTwoAmount, _bidSizeTwoAmountOut);
        _createBid(_bidSizeTwoAmount, _bidSizeTwoAmountOut);
        _createBid(_bidPriceOneAmount, _bidPriceOneAmountOut);
        _createBid(_bidPriceOneAmount, _bidPriceOneAmountOut);
        _;
    }

    // ============ Tests ============ //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the lot has not concluded
    //   [X] it reverts
    // [X] when the lot has not been decrypted
    //   [X] it reverts
    // [X] when the lot has been settled already
    //   [X] it reverts
    // [ ] when the marginal price overflows
    //  [ ] it reverts

    function test_invalidLotId_reverts() external {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_InvalidId.selector, _lotId);
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    function test_lotNotConcluded_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            EncryptedMarginalPriceAuction.Auction_MarketActive.selector, _lotId
        );
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    function test_lotNotDecrypted_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    function test_lotAlreadySettled_reverts()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsSettled
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(EncryptedMarginalPriceAuction.Auction_WrongState.selector);
        vm.expectRevert(err);

        // Call function
        _auctionHouse.settle(_lotId);
    }

    // [X] when the filled amount is less than the lot minimum
    //   [ ] it returns no winning bids, and the base tokens are returned to the owner
    // [ ] when the marginal price is less than the minimum price
    //   [ ] it returns no winning bids, and the base tokens are returned to the owner
    // [ ] given the lot is over-subscribed with a partial fill
    //  [ ] it returns winning bids, with the marginal price is the price at which the lot capacity is exhausted, and a partial fill for the lowest winning bid, last bidder receives the partial fill and is returned excess quote tokens
    // [ ] given the filled capacity is greater than the lot minimum
    //  [ ] it returns winning bids, with the marginal price is the minimum price
    // [ ] given some of the bids fall below the minimum price
    //  [ ] it returns winning bids, excluding those below the minimum price
    // [ ] given the auction house has insufficient balance of the quote token
    //  [ ] it reverts
    // [ ] given the auction house has insufficient balance of the base token
    //  [ ] it reverts
    // [ ] given that the quote token decimals differ from the base token decimals
    //  [ ] it succeeds
    // [ ] it succeeds - auction owner receives quote tokens (minus fees), bidders receive base tokens and fees accrued

    function test_bidsLessThanMinimumFilled()
        external
        givenOwnerHasBaseTokenBalance(_LOT_CAPACITY)
        givenOwnerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenBidsAreBelowMinimumFilled
        givenLotHasConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
    {
        // Call function
        _auctionHouse.settle(_lotId);

        // Validate bid data
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);
        assertEq(bidData.marginalPrice, 0);

        // Validate lot data
        EncryptedMarginalPriceAuction.Lot memory lot = _getLotData(_lotId);
        assertEq(uint8(lot.status), uint8(EncryptedMarginalPriceAuction.AuctionStatus.Settled));

        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)), 0, "base token: auction house balance"
        );
        assertEq(_baseToken.balanceOf(_auctionOwner), _LOT_CAPACITY, "base token: owner balance");
        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder balance");
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: bidder two balance");
        assertEq(_baseToken.balanceOf(_CURATOR), 0, "base token: curator balance");
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");
    }

    // TODO decimals

    // [ ] given there is no referrer fee set for the auction type
    //  [ ] no referrer fee is accrued
    // [ ] the referrer fee is accrued

    // [ ] given there is a curator set
    //  [ ] given the payout token is a derivative
    //   [ ] derivative is minted and transferred to the curator
    //  [ ] payout token is transferred to the curator
}
