// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {IBatchAuction} from "src/interfaces/modules/IBatchAuction.sol";
import {BatchAuctionModule} from "src/modules/auctions/BatchAuctionModule.sol";

import {BatchAuctionHouseTest} from "test/BatchAuctionHouse/AuctionHouseTest.sol";

contract BatchClaimBidsTest is BatchAuctionHouseTest {
    uint256 internal constant _BID_AMOUNT = 1e18;
    uint256 internal constant _BID_AMOUNT_OUT = 2e18;

    address internal constant _BIDDER_TWO = address(0x20);

    bytes internal constant _ON_SETTLE_CALLBACK_PARAMS = "";

    IBatchAuction.BidClaim[] internal _bidClaims;

    uint256 internal _expectedBidderQuoteTokenBalance;
    uint256 internal _expectedBidderTwoQuoteTokenBalance;
    uint256 internal _expectedAuctionHouseQuoteTokenBalance;

    uint256 internal _expectedBidderBaseTokenBalance;
    uint256 internal _expectedBidderTwoBaseTokenBalance;
    uint256 internal _expectedAuctionHouseBaseTokenBalance;
    uint256 internal _expectedCuratorBaseTokenBalance;

    uint256 internal _expectedReferrerFee;
    uint256 internal _expectedProtocolFee;

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction module reverts
    //  [X] it reverts
    // [X] when the paid and payout amounts are both set
    //  [X] it transfers the quote and base tokens to the bidder, and calculates fees correctly
    // [X] when the payout is not set
    //  [X] it returns the bid amount to the bidders
    // [X] when the referrer is set
    //  [X] it sends the payout to the bidders, and allocates fees to the referrer and protocol
    // [X] it sends the payout to the bidders, and allocates referrer and protocol fees to the protocol
    // [X] when the protocol fee is changed before claim
    //  [X] it allocates the cached fee
    // [X] when the referrer fee is changed before the claim
    //  [X] it allocates the cached fee
    // [X] when the caller is not the bidder
    //  [X] it transfers the payout to the bidder
    // [X] given the bids have different outcomes
    //  [X] it handles the transfers correctly

    // ============ Helper Functions ============

    function _assertAccruedFees() internal {
        // Check accrued quote token fees
        assertEq(
            _auctionHouse.rewards(_REFERRER, _quoteToken), _expectedReferrerFee, "referrer fee"
        );
        assertEq(_auctionHouse.rewards(_CURATOR, _quoteToken), 0, "curator fee"); // Always 0
        assertEq(
            _auctionHouse.rewards(_PROTOCOL, _quoteToken), _expectedProtocolFee, "protocol fee"
        );
    }

    function _assertBaseTokenBalances() internal {
        // Check base token balances
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _expectedAuctionHouseBaseTokenBalance,
            "base token: auction house balance"
        );
        assertEq(
            _baseToken.balanceOf(_bidder),
            _expectedBidderBaseTokenBalance,
            "base token: bidder balance"
        );
        assertEq(
            _baseToken.balanceOf(_BIDDER_TWO),
            _expectedBidderTwoBaseTokenBalance,
            "base token: bidder two balance"
        );
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(
            _baseToken.balanceOf(_CURATOR),
            _expectedCuratorBaseTokenBalance,
            "base token: curator balance"
        );
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");

        IAuctionHouse.Routing memory routing = _getLotRouting(_lotId);
        assertEq(routing.funding, _expectedAuctionHouseBaseTokenBalance, "funding");
    }

    function _assertQuoteTokenBalances() internal {
        // Check quote token balances
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)),
            _expectedAuctionHouseQuoteTokenBalance,
            "quote token: auction house balance"
        );
        assertEq(
            _quoteToken.balanceOf(_bidder),
            _expectedBidderQuoteTokenBalance,
            "quote token: bidder balance"
        );
        assertEq(
            _quoteToken.balanceOf(_BIDDER_TWO),
            _expectedBidderTwoQuoteTokenBalance,
            "quote token: bidder two balance"
        );
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function _mockAuctionModuleReverts() internal {
        vm.mockCallRevert(
            address(_auctionModule),
            abi.encodeWithSelector(BatchAuctionModule.claimBids.selector, _lotId, _bidIds),
            "revert"
        );
    }

    modifier givenAuctionModuleReverts() {
        _mockAuctionModuleReverts();
        _;
    }

    /// @dev    Assumes that any amounts are scaled to the current decimal scale
    modifier givenPayoutIsNotSet(
        uint64 bidId_,
        address bidder_,
        address referrer_,
        uint256 amountIn_
    ) {
        _batchAuctionModule.addBidClaim(
            _lotId, bidId_, bidder_, referrer_, uint96(amountIn_), uint96(0), uint96(amountIn_)
        );

        // Calculate fees
        (uint256 toReferrer, uint256 toProtocol,) = _calculateFees(referrer_, 0);
        _expectedReferrerFee += toReferrer;
        _expectedProtocolFee += toProtocol;

        // Set expected balances
        _expectedAuctionHouseQuoteTokenBalance += 0; // any tokens are returned to the bidder
        _expectedBidderQuoteTokenBalance += bidder_ == _bidder ? amountIn_ : 0; // Returned to the bidder
        _expectedBidderTwoQuoteTokenBalance += bidder_ == _BIDDER_TWO ? amountIn_ : 0; // Returned to the bidder

        _expectedBidderBaseTokenBalance += 0;
        _expectedCuratorBaseTokenBalance += 0;
        _;
    }

    /// @dev    Assumes that any amounts are scaled to the current decimal scale
    modifier givenPayoutIsSet(
        uint64 bidId_,
        address bidder_,
        address referrer_,
        uint256 amountIn_,
        uint256 payout_
    ) {
        _batchAuctionModule.addBidClaim(
            _lotId, bidId_, bidder_, referrer_, uint96(amountIn_), uint96(payout_), uint96(0)
        );

        // Calculate fees
        (uint256 toReferrer, uint256 toProtocol,) = _calculateFees(referrer_, amountIn_);
        _expectedReferrerFee += toReferrer;
        _expectedProtocolFee += toProtocol;

        // Set expected balances
        _expectedAuctionHouseQuoteTokenBalance += toReferrer + toProtocol;
        _expectedBidderQuoteTokenBalance += 0;

        _expectedBidderBaseTokenBalance += bidder_ == _bidder ? payout_ : 0;
        _expectedBidderTwoBaseTokenBalance += bidder_ == _BIDDER_TWO ? payout_ : 0;
        _expectedCuratorBaseTokenBalance += 0;
        _;
    }

    /// @dev    Assumes that any amounts are scaled to the current decimal scale
    modifier givenPayoutIsPartial(
        uint64 bidId_,
        address bidder_,
        address referrer_,
        uint256 amountIn_,
        uint256 payout_,
        uint256 refund_
    ) {
        _batchAuctionModule.addBidClaim(
            _lotId, bidId_, bidder_, referrer_, uint96(amountIn_), uint96(payout_), uint96(refund_)
        );

        // Calculate fees
        (uint256 toReferrer, uint256 toProtocol, uint256 totalFees) =
            _calculateFees(referrer_, amountIn_ - refund_);
        _expectedReferrerFee += toReferrer;
        _expectedProtocolFee += toProtocol;

        // Set expected balances
        _expectedAuctionHouseQuoteTokenBalance += totalFees;
        _expectedBidderQuoteTokenBalance += bidder_ == _bidder ? refund_ : 0;
        _expectedBidderTwoQuoteTokenBalance += bidder_ == _BIDDER_TWO ? refund_ : 0;

        _expectedBidderBaseTokenBalance += bidder_ == _bidder ? payout_ : 0;
        _expectedBidderTwoBaseTokenBalance += bidder_ == _BIDDER_TWO ? payout_ : 0;
        _expectedCuratorBaseTokenBalance += 0;
        _;
    }

    modifier givenLotSettlementIsMixed() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            true
        );

        _auctionHouse.settle(_lotId, 100_000, _ON_SETTLE_CALLBACK_PARAMS);
        _;
    }

    modifier givenLotSettlementIsPartialFill() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            _scaleQuoteTokenAmount(_BID_AMOUNT + _BID_AMOUNT / 2),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT + _BID_AMOUNT_OUT),
            true
        );

        _auctionHouse.settle(_lotId, 100_000, _ON_SETTLE_CALLBACK_PARAMS);
        _;
    }

    modifier givenLotSettlementIsSuccessful() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            _scaleQuoteTokenAmount(_BID_AMOUNT + _BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT + _BID_AMOUNT_OUT),
            true
        );

        _auctionHouse.settle(_lotId, 100_000, _ON_SETTLE_CALLBACK_PARAMS);
        _;
    }

    modifier givenLotSettlementIsNotSuccessful() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(_lotId, 0, 0, true);

        // Payout tokens will be returned to the seller
        _auctionHouse.settle(_lotId, 100_000, _ON_SETTLE_CALLBACK_PARAMS);
        _;
    }

    modifier givenBidderTwoHasQuoteTokenBalance(uint256 amount_) {
        _quoteToken.mint(_BIDDER_TWO, amount_);
        _;
    }

    modifier givenBidderTwoHasQuoteTokenAllowance(uint256 amount_) {
        vm.prank(_BIDDER_TWO);
        _quoteToken.approve(address(_auctionHouse), amount_);
        _;
    }

    // ============ Tests ============

    function test_invalidLotId_reverts() external {
        bytes memory err = abi.encodeWithSelector(IAuctionHouse.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);
    }

    function test_auctionModuleReverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenAuctionModuleReverts
    {
        vm.expectRevert("revert");

        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);
    }

    function test_givenNoPayout()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsNotSet(_bidIds[0], _bidder, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenPayoutIsNotSet(_bidIds[1], _BIDDER_TWO, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenNoPayout_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsNotSet(_bidIds[0], _bidder, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenPayoutIsNotSet(_bidIds[1], _BIDDER_TWO, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenNoPayout_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsNotSet(_bidIds[0], _bidder, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenPayoutIsNotSet(_bidIds[1], _BIDDER_TWO, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenNoPayout_givenProtocolFeeIsChanged()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsNotSet(_bidIds[0], _bidder, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenPayoutIsNotSet(_bidIds[1], _BIDDER_TWO, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Change the protocol fee
        _setProtocolFee(90);

        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        // Assertions are not updated with the new fee, so the test will fail if the new fee is used by the AuctionHouse
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_givenProtocolFeeIsChanged()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Change the protocol fee
        _setProtocolFee(90);

        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        // Assertions are not updated with the new fee, so the test will fail if the new fee is used by the AuctionHouse
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrer()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrer_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrer_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noProtocolFee()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noProtocolFee_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noProtocolFee_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrerFee()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrerFee_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrerFee_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrerFee_noProtocolFee()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrerFee_noProtocolFee_quoteTokenDecimalsLarger()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrerFee_noProtocolFee_quoteTokenDecimalsSmaller()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsSet(
            _bidIds[1],
            _BIDDER_TWO,
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenDifferentOutcomes()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsNotSet(_bidIds[1], _BIDDER_TWO, _REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT))
        givenLotIsConcluded
        givenLotSettlementIsMixed
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPartialFill()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenMaxReferrerFeeIsSet
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_bidder, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenBidderTwoHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidderTwoHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBidCreated(_BIDDER_TWO, _scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _bidIds[0],
            _bidder,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT)
        )
        givenPayoutIsPartial(
            _bidIds[1],
            _BIDDER_TWO,
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _scaleQuoteTokenAmount(_BID_AMOUNT / 2)
        )
        givenLotIsConcluded
        givenLotSettlementIsPartialFill
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBids(_lotId, _bidIds);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }
}
