// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Auction, AuctionModule} from "src/modules/Auction.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

import {console2} from "forge-std/console2.sol";

contract ClaimBidTest is AuctionHouseTest {
    uint96 internal constant _BID_AMOUNT = 1e18;
    uint96 internal constant _BID_AMOUNT_OUT = 2e18;

    uint256 internal _expectedBidderQuoteTokenBalance;
    uint256 internal _expectedAuctionHouseQuoteTokenBalance;

    uint256 internal _expectedBidderBaseTokenBalance;
    uint256 internal _expectedAuctionHouseBaseTokenBalance;
    uint256 internal _expectedCuratorBaseTokenBalance;

    uint256 internal _expectedReferrerFee;
    uint256 internal _expectedProtocolFee;

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] when the auction module reverts
    //  [X] it reverts
    // [X] when the payout is not set
    //  [X] when the caller is not the bidder
    //   [X] it refunds the bid amount to the bidder
    //  [X] it returns the bid amount to the bidder
    // [X] when the referrer is set
    //  [X] it sends the payout to the bidder, and allocates fees to the referrer and protocol
    // [X] it sends the payout to the bidder, and allocates referrer and protocol fees to the protocol
    // [X] when the protocol fee is changed before claim
    //  [X] it uses the cached fee
    // [X] when the referrer fee is changed before the claim
    //  [X] it uses the cached fee
    // [X] when the caller is not the bidder
    //  [X] it transfers the payout to the bidder

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
        assertEq(_baseToken.balanceOf(_REFERRER), 0, "base token: referrer balance");
        assertEq(
            _baseToken.balanceOf(_CURATOR),
            _expectedCuratorBaseTokenBalance,
            "base token: curator balance"
        );
        assertEq(_baseToken.balanceOf(_PROTOCOL), 0, "base token: protocol balance");
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
        assertEq(_quoteToken.balanceOf(_REFERRER), 0, "quote token: referrer balance");
        assertEq(_quoteToken.balanceOf(_CURATOR), 0, "quote token: curator balance");
        assertEq(_quoteToken.balanceOf(_PROTOCOL), 0, "quote token: protocol balance");
    }

    function _mockAuctionModuleReverts(address sender_) internal {
        vm.mockCallRevert(
            address(_auctionModule),
            abi.encodeWithSelector(AuctionModule.claimBid.selector, _lotId, _bidId, sender_),
            "revert"
        );
    }

    function _mockClaimBid(
        address referrer_,
        uint256 paid_,
        uint256 payout_,
        address sender_
    ) internal {
        vm.mockCall(
            address(_auctionModule),
            abi.encodeWithSelector(AuctionModule.claimBid.selector, _lotId, _bidId, sender_),
            abi.encode(
                Auction.BidClaim({
                    bidder: _bidder,
                    referrer: referrer_,
                    paid: paid_,
                    payout: payout_
                }),
                ""
            )
        );
    }

    modifier givenAuctionModuleReverts(address sender_) {
        _mockAuctionModuleReverts(sender_);
        _;
    }

    modifier givenLotIsPrefunded() {
        _batchAuctionModule.setRequiredPrefunding(true);
        _;
    }

    function _calculateFees(
        address referrer_,
        uint256 amountIn_
    ) internal view returns (uint256 toReferrer, uint256 toProtocol) {
        bool hasReferrer = referrer_ != address(0);

        uint256 referrerFee = uint256(amountIn_) * _referrerFeePercentActual / 1e5;

        // If the referrer is not set, the referrer fee is allocated to the protocol
        toReferrer = hasReferrer ? referrerFee : 0;
        toProtocol =
            uint256(amountIn_) * _protocolFeePercentActual / 1e5 + (hasReferrer ? 0 : referrerFee);

        return (toReferrer, toProtocol);
    }

    /// @dev    Assumes that any amounts are scaled to the current decimal scale
    modifier givenPayoutIsNotSet(address referrer_, uint96 amountIn_, address sender_) {
        uint96 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _mockClaimBid(referrer_, amountIn_, 0, sender_);

        // Calculate fees
        (uint256 toReferrer, uint256 toProtocol) = _calculateFees(referrer_, 0);
        _expectedReferrerFee += toReferrer;
        _expectedProtocolFee += toProtocol;

        // Set expected balances
        _expectedAuctionHouseQuoteTokenBalance += 0; // No fees are collected
        _expectedBidderQuoteTokenBalance = amountIn_; // Returned to the bidder

        _expectedAuctionHouseBaseTokenBalance = 0; // Returned to the seller during settlement
        _expectedBidderBaseTokenBalance = 0;
        _expectedCuratorBaseTokenBalance = 0;
        _;
    }

    /// @dev    Assumes that any amounts are scaled to the current decimal scale
    modifier givenPayoutIsSet(
        address referrer_,
        uint96 amountIn_,
        uint96 payout_,
        address sender_
    ) {
        uint96 scaledLotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _mockClaimBid(referrer_, amountIn_, payout_, sender_);

        // Calculate fees
        (uint256 toReferrer, uint256 toProtocol) = _calculateFees(referrer_, amountIn_);
        _expectedReferrerFee += toReferrer;
        _expectedProtocolFee += toProtocol;

        // Set expected balances
        _expectedAuctionHouseQuoteTokenBalance += toReferrer + toProtocol; // Payment sent to the seller during settlement
        _expectedBidderQuoteTokenBalance += 0;

        _expectedAuctionHouseBaseTokenBalance = 0; // Returned to the seller during settlement
        _expectedBidderBaseTokenBalance = payout_;
        _expectedCuratorBaseTokenBalance = 0;
        _;
    }

    modifier givenLotSettlementIsSuccessful() {
        // Set the settlement data
        _batchAuctionModule.setLotSettlement(
            _lotId,
            Auction.Settlement({
                totalIn: _scaleQuoteTokenAmount(_BID_AMOUNT),
                totalOut: _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
                pfBidder: address(0),
                pfReferrer: address(0),
                pfRefund: 0,
                pfPayout: 0,
                auctionOutput: ""
            })
        );

        _auctionHouse.settle(_lotId);
        _;
    }

    modifier givenLotSettlementIsNotSuccessful() {
        // Payout tokens will be returned to the seller
        _auctionHouse.settle(_lotId);
        _;
    }

    // ============ Tests ============

    function test_invalidLotId_reverts() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);
    }

    function test_auctionModuleReverts()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenAuctionModuleReverts(_bidder)
    {
        vm.expectRevert("revert");

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);
    }

    function test_givenNoPayout()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsNotSet(_REFERRER, _BID_AMOUNT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsNotSet(_REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT), _bidder)
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsNotSet(_REFERRER, _scaleQuoteTokenAmount(_BID_AMOUNT), _bidder)
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenNoPayout_givenReferrerFeeIsChanged()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsNotSet(_REFERRER, _BID_AMOUNT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Change the referrer fee
        _setReferrerFee(90);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        // Assertions are not updated with the new fee, so the test will fail if the new fee is used by the AuctionHouse
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenNoPayout_givenProtocolFeeIsChanged()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsNotSet(_REFERRER, _BID_AMOUNT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Change the protocol fee
        _setProtocolFee(90);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        // Assertions are not updated with the new fee, so the test will fail if the new fee is used by the AuctionHouse
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenNoPayout_whenCallerIsNotBidder()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsNotSet(_REFERRER, _BID_AMOUNT, address(this))
        givenLotIsConcluded
        givenLotSettlementIsNotSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsSet(_REFERRER, _BID_AMOUNT, _BID_AMOUNT_OUT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_givenReferrerFeeIsChanged()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsSet(_REFERRER, _BID_AMOUNT, _BID_AMOUNT_OUT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Change the referrer fee
        _setReferrerFee(90);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        // Assertions are not updated with the new fee, so the test will fail if the new fee is used by the AuctionHouse
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_givenProtocolFeeIsChanged()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsSet(_REFERRER, _BID_AMOUNT, _BID_AMOUNT_OUT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Change the protocol fee
        _setProtocolFee(90);

        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        // Assertions are not updated with the new fee, so the test will fail if the new fee is used by the AuctionHouse
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_whenCallerIsNotBidder()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsSet(_REFERRER, _BID_AMOUNT, _BID_AMOUNT_OUT, address(this))
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(address(this));
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }

    function test_givenPayout_noReferrer()
        external
        whenAuctionTypeIsBatch
        whenBatchAuctionModuleIsInstalled
        givenCuratorIsSet
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsSet(address(0), _BID_AMOUNT, _BID_AMOUNT_OUT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsSet(_REFERRER, _BID_AMOUNT, _BID_AMOUNT_OUT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenReferrerFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            _REFERRER,
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsSet(address(0), _BID_AMOUNT, _BID_AMOUNT_OUT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenProtocolFeeIsSet
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBid(_BID_AMOUNT, "")
        givenPayoutIsSet(address(0), _BID_AMOUNT, _BID_AMOUNT_OUT, _bidder)
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(17)
        givenBaseTokenHasDecimals(13)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

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
        givenLotIsPrefunded
        givenQuoteTokenHasDecimals(13)
        givenBaseTokenHasDecimals(17)
        givenSellerHasBaseTokenBalance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenSellerHasBaseTokenAllowance(_scaleBaseTokenAmount(_LOT_CAPACITY))
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenUserHasQuoteTokenAllowance(_scaleQuoteTokenAmount(_BID_AMOUNT))
        givenBid(_scaleQuoteTokenAmount(_BID_AMOUNT), "")
        givenPayoutIsSet(
            address(0),
            _scaleQuoteTokenAmount(_BID_AMOUNT),
            _scaleBaseTokenAmount(_BID_AMOUNT_OUT),
            _bidder
        )
        givenLotIsConcluded
        givenLotSettlementIsSuccessful
    {
        // Call the function
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, _bidId);

        // Check the accrued fees
        _assertAccruedFees();
        _assertQuoteTokenBalances();
        _assertBaseTokenBalances();
    }
}
