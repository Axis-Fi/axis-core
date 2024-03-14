// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";
import {Point, ECIES} from "src/lib/ECIES.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";
import {Auction} from "src/modules/Auction.sol";
import {Router} from "src/AuctionHouse.sol";

import {keycodeFromVeecode, fromVeecode} from "src/modules/Modules.sol";

import {AuctionHouseTest} from "test/AuctionHouse/AuctionHouseTest.sol";

contract LinearVestingEMPAIntegrationTest is AuctionHouseTest {
    EncryptedMarginalPriceAuctionModule internal _empaModule;
    LinearVesting internal _linearVestingModule;

    uint256 internal constant _AUCTION_PRIVATE_KEY = 112_233_445_566;
    Point internal _auctionPublicKey;

    uint128 internal constant _BID_SEED = 12_345_678_901_234_567_890_123_456_789_012_345_678;
    uint256 internal constant _BID_PRIVATE_KEY = 112_233_445_566_778;
    Point internal _bidPublicKey;

    EncryptedMarginalPriceAuctionModule.AuctionDataParams internal _auctionDataParams;
    uint96 internal constant _MIN_PRICE = 1e18;
    uint24 internal constant _MIN_FILL_PERCENT = 25_000; // 25%
    uint24 internal constant _MIN_BID_PERCENT = 1000; // 1%

    LinearVesting.VestingParams internal _linearVestingParams;
    uint48 internal constant _VESTING_START = 1_704_882_344; // 2024-01-10
    uint48 internal constant _VESTING_EXPIRY = 1_705_055_144; // 2024-01-12
    uint48 internal constant _VESTING_DURATION = _VESTING_EXPIRY - _VESTING_START;

    uint96 internal constant _BID_AMOUNT = 15e18;
    uint96 internal constant _BID_AMOUNT_OUT = 10e18; // Ensures that capacit is filled and the price is not adjusted

    // ============ Modifiers ============ //

    modifier givenAuctionTypeIsEMPA() {
        _empaModule = new EncryptedMarginalPriceAuctionModule(address(_auctionHouse));
        _auctionHouse.installModule(_empaModule);
        _auctionModule = _empaModule;
        _auctionModuleKeycode = keycodeFromVeecode(_empaModule.VEECODE());

        _routingParams.auctionType = keycodeFromVeecode(_empaModule.VEECODE());
        _routingParams.prefunded = true;

        _auctionPublicKey = ECIES.calcPubKey(Point(1, 2), _AUCTION_PRIVATE_KEY);
        _bidPublicKey = ECIES.calcPubKey(Point(1, 2), _BID_PRIVATE_KEY);

        _auctionDataParams = EncryptedMarginalPriceAuctionModule.AuctionDataParams({
            minPrice: _MIN_PRICE,
            minFillPercent: _MIN_FILL_PERCENT,
            minBidPercent: _MIN_BID_PERCENT,
            publicKey: _auctionPublicKey
        });
        _auctionParams.implParams = abi.encode(_auctionDataParams);
        _;
    }

    modifier givenDerivativeTypeIsLinearVesting() {
        _linearVestingModule = new LinearVesting(address(_auctionHouse));
        _auctionHouse.installModule(_linearVestingModule);
        _derivativeModuleKeycode = keycodeFromVeecode(_linearVestingModule.VEECODE());

        _routingParams.derivativeType = keycodeFromVeecode(_linearVestingModule.VEECODE());

        _linearVestingParams =
            LinearVesting.VestingParams({start: _VESTING_START, expiry: _VESTING_EXPIRY});
        _routingParams.derivativeParams = abi.encode(_linearVestingParams);
        _;
    }

    function _formatBid(uint128 amountOut_) internal pure returns (uint256) {
        uint256 formattedAmountOut;
        {
            uint128 subtracted;
            unchecked {
                subtracted = amountOut_ - _BID_SEED;
            }
            formattedAmountOut = uint256(bytes32(abi.encodePacked(_BID_SEED, subtracted)));
        }

        return formattedAmountOut;
    }

    function _encryptBid(
        uint96 lotId_,
        address bidder_,
        uint96 amountIn_,
        uint128 amountOut_,
        uint256 auctionPrivateKey_
    ) internal view returns (uint256) {
        // Format the amount out
        uint256 formattedAmountOut = _formatBid(amountOut_);

        Point memory sharedSecretKey = ECIES.calcPubKey(_bidPublicKey, auctionPrivateKey_); // TODO is the use of the private key here correct?
        uint256 salt = uint256(keccak256(abi.encodePacked(lotId_, bidder_, amountIn_)));
        uint256 symmetricKey = uint256(keccak256(abi.encodePacked(sharedSecretKey.x, salt)));

        return formattedAmountOut ^ symmetricKey;
    }

    function _createBidData(
        address bidder_,
        uint96 amountIn_,
        uint96 amountOut_
    ) internal view returns (bytes memory) {
        uint256 encryptedAmountOut =
            _encryptBid(_lotId, bidder_, amountIn_, amountOut_, _AUCTION_PRIVATE_KEY);

        return abi.encode(encryptedAmountOut, _bidPublicKey);
    }

    function _createBid(
        address bidder_,
        uint96 amountIn_,
        uint96 amountOut_
    ) internal returns (uint64 bidId) {
        bytes memory bidData = _createBidData(bidder_, amountIn_, amountOut_);

        Router.BidParams memory bid = Router.BidParams({
            lotId: _lotId,
            referrer: _REFERRER,
            amount: amountIn_,
            auctionData: bidData,
            permit2Data: ""
        });

        vm.prank(_bidder);
        bidId = _auctionHouse.bid(bid, bytes(""));
        _bidIds.push(bidId);

        return bidId;
    }

    modifier givenBidIsCreated(uint96 amountIn_, uint96 amountOut_) {
        _createBid(_bidder, amountIn_, amountOut_);
        _;
    }

    function _submitPrivateKey() internal {
        _empaModule.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);
    }

    modifier givenPrivateKeyIsSubmitted() {
        _submitPrivateKey();
        _;
    }

    function _decryptLot() internal {
        _empaModule.decryptAndSortBids(_lotId, 10);
    }

    modifier givenLotIsDecrypted() {
        _decryptLot();
        _;
    }

    // ============ Tests ============ //

    // auction
    // [X] it creates the auction with the correct parameters

    function test_auction()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
    {
        // Check the routing parameters
        Auctioneer.Routing memory lotRouting = _getLotRouting(_lotId);
        assertEq(
            fromVeecode(lotRouting.auctionReference),
            fromVeecode(_empaModule.VEECODE()),
            "auctionReference"
        );
        assertEq(lotRouting.seller, _SELLER, "seller");
        assertEq(address(lotRouting.baseToken), address(_baseToken), "base token");
        assertEq(address(lotRouting.quoteToken), address(_quoteToken), "quote token");
        assertEq(address(lotRouting.callbacks), address(0), "callbacks");
        assertEq(
            fromVeecode(lotRouting.derivativeReference), fromVeecode(_linearVestingModule.VEECODE())
        );
        assertEq(lotRouting.derivativeParams, abi.encode(_linearVestingParams), "derivativeParams");
        assertEq(lotRouting.wrapDerivative, false, "wrapDerivative");
        assertEq(lotRouting.funding, _LOT_CAPACITY, "funding");

        // Check balances
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller balance");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), _LOT_CAPACITY, "seller balance");
    }

    // cancel
    // [X] it cancels the auction

    function test_cancel()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotIsCancelled
    {
        // Check the auction data
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData =
            _empaModule.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Claimed), "status");

        // Check balances
        assertEq(_baseToken.balanceOf(_SELLER), _LOT_CAPACITY, "seller balance");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 0, "auction house balance");
    }

    // purchase
    // [X] it reverts

    function test_purchase_reverts()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_NotImplemented.selector);
        vm.expectRevert(err);

        // Call function
        _createPurchase(_BID_AMOUNT, _BID_AMOUNT_OUT, "");
    }

    // bid
    // [X] the bid is placed correctly

    function test_bid()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
    {
        // Check the bid
        (
            EncryptedMarginalPriceAuctionModule.Bid memory bid,
            EncryptedMarginalPriceAuctionModule.EncryptedBid memory encryptedBid
        ) = _empaModule.getBid(_lotId, 1);

        assertEq(bid.bidder, _bidder, "bidder");
        assertEq(bid.amount, _BID_AMOUNT, "amountIn");
        assertEq(bid.minAmountOut, 0, "amountOut");
        assertEq(bid.referrer, _REFERRER, "referrer");
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Submitted),
            "status"
        );

        assertEq(encryptedBid.bidPubKey.x, _bidPublicKey.x, "bidPubKey.x");
        assertEq(encryptedBid.bidPubKey.y, _bidPublicKey.y, "bidPubKey.y");

        // Check balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token balance");
    }

    // submitPrivateKey
    // [X] the private key is submitted correctly

    function test_submitPrivateKey()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotIsConcluded
        givenPrivateKeyIsSubmitted
    {
        // Check the auction
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData =
            _empaModule.getAuctionData(_lotId);
        assertEq(auctionData.privateKey, _AUCTION_PRIVATE_KEY, "privateKey");

        // Check the bid
        (EncryptedMarginalPriceAuctionModule.Bid memory bid,) = _empaModule.getBid(_lotId, 1);

        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Submitted),
            "status"
        );
    }

    // decrypt
    // [X] the decryption is successful

    function test_decrypt()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotIsConcluded
        givenPrivateKeyIsSubmitted
    {
        // Decrypt bids
        _empaModule.decryptAndSortBids(_lotId, 1);

        // Check the auction
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData =
            _empaModule.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Decrypted), "status");

        // Check the bid
        (EncryptedMarginalPriceAuctionModule.Bid memory bid,) = _empaModule.getBid(_lotId, 1);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "status"
        );
        assertEq(bid.minAmountOut, _BID_AMOUNT_OUT, "minAmountOut");
    }

    // settle
    // [X] the auction is settled
    // [X] given curation is enabled
    //  [X] the curation fee is sent to the curator, but cannot be transferred

    function test_settle()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotIsConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Check the auction
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData =
            _empaModule.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Check the lot
        Auction.Lot memory lotData = _getLotData(_lotId);
        assertEq(lotData.purchased, _BID_AMOUNT, "purchased");
        assertEq(lotData.sold, _BID_AMOUNT_OUT, "sold");
        assertEq(lotData.partialPayout, 0, "partial payout");

        // Get the derivative token id
        uint256 derivativeTokenId =
            _linearVestingModule.computeId(address(_baseToken), abi.encode(_linearVestingParams));

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: bidder");
        assertEq(
            _quoteToken.balanceOf(address(_auctionHouse)), _BID_AMOUNT, "quote token: auction house"
        ); // Bid amount

        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 10e18, "base token: auction house"); // Base tokens to be claimed + unused capacity
        assertEq(
            _baseToken.balanceOf(address(_linearVestingModule)), 0, "base token: vesting module"
        );

        assertEq(
            _linearVestingModule.balanceOf(_bidder, derivativeTokenId), 0, "derivative: bidder"
        );
    }

    function test_settle_givenCurated()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenCuratorIsSet
        givenLotIsCreated
        givenCuratorMaxFeeIsSet
        givenCuratorFeeIsSet
        givenLotHasStarted
        givenSellerHasBaseTokenBalance(_curatorMaxPotentialFee)
        givenSellerHasBaseTokenAllowance(_curatorMaxPotentialFee)
        givenCuratorHasApproved
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotIsConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
    {
        // Check the auction
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData =
            _empaModule.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Settled), "status");

        // Get the derivative token id
        uint256 derivativeTokenId =
            _linearVestingModule.computeId(address(_baseToken), abi.encode(_linearVestingParams));

        // Check that the curator has been paid in derivative token
        uint256 expectedCuratorFee = _BID_AMOUNT_OUT * _curatorFeePercentActual / 1e5;
        assertEq(
            _linearVestingModule.balanceOf(_CURATOR, derivativeTokenId),
            expectedCuratorFee,
            "curator fee"
        );
        assertEq(_linearVestingModule.redeemable(_CURATOR, derivativeTokenId), 0, "redeemable");
    }

    function test_settle_partialFill()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(8e18 + 4e18)
        givenUserHasQuoteTokenAllowance(8e18 + 4e18)
    {
        // Create bids
        _createBid(_bidder, 8e18, 4e18); // 1: marginal price 2, totalIn 8, capacity at 4/10
        _createBid(_bidder, 4e18, 4e18); // 2: marginal price 1, totalIn 12, capacity at 12/10

        // Conclude and settle
        _concludeLot();
        _submitPrivateKey();
        _decryptLot();
        _settleLot();

        // Check the bids
        (EncryptedMarginalPriceAuctionModule.Bid memory bid1,) = _empaModule.getBid(_lotId, 1);
        assertEq(
            uint8(bid1.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Decrypted),
            "bid 1: status"
        );
        (EncryptedMarginalPriceAuctionModule.Bid memory bid2,) = _empaModule.getBid(_lotId, 2);
        assertEq(
            uint8(bid2.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "bid 2: status"
        );

        // Check the lot
        Auction.Lot memory lotData = _getLotData(_lotId);
        assertEq(lotData.purchased, 10e18, "purchased");
        assertEq(lotData.sold, 10e18, "sold");
        assertEq(lotData.partialPayout, 2e18, "partial payout");

        // Get the derivative token id
        uint256 derivativeTokenId =
            _linearVestingModule.computeId(address(_baseToken), abi.encode(_linearVestingParams));

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 2e18, "quote token: bidder"); // Partial fill: refund
        assertEq(_quoteToken.balanceOf(address(_auctionHouse)), 10e18, "quote token: auction house");

        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder");
        assertEq(_baseToken.balanceOf(address(_auctionHouse)), 8e18, "base token: auction house");
        assertEq(
            _baseToken.balanceOf(address(_linearVestingModule)), 2e18, "base token: vesting module"
        );

        assertEq(
            _linearVestingModule.balanceOf(_bidder, derivativeTokenId), 2e18, "derivative: bidder"
        ); // Partial fill: payout
    }

    // TODO assert roundtrip numbers

    // claimProceeds
    // [X] quote tokens are sent to the seller and excess capacity is returned to the seller

    function test_claimProceeds()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotIsConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
        givenLotProceedsAreClaimed
    {
        // Check the auction state
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData =
            _empaModule.getAuctionData(_lotId);
        assertEq(uint8(auctionData.status), uint8(Auction.Status.Claimed), "status");

        // Check the balances
        assertEq(_quoteToken.balanceOf(_SELLER), _BID_AMOUNT, "seller balance");
        assertEq(_baseToken.balanceOf(_SELLER), _LOT_CAPACITY - _BID_AMOUNT_OUT, "seller balance");
    }

    // claimBid
    // [X] derivative tokens are minted to the bidder, but cannot be transferred
    // [X] given the expiry time has passed, the derivative tokens can be redeemed for the base tokens

    function test_claimBid_refund()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(4e18)
        givenUserHasQuoteTokenAllowance(4e18)
        givenBidIsCreated(4e18, 5e18) // Below the minimum price
        givenLotIsConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
        givenBidIsClaimed(1)
    {
        // Check the bid
        (EncryptedMarginalPriceAuctionModule.Bid memory bid,) = _empaModule.getBid(_lotId, 1);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );

        uint256 derivativeTokenId =
            _linearVestingModule.computeId(address(_baseToken), abi.encode(_linearVestingParams));

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 4e18, "quote token: bidder");

        assertEq(_linearVestingModule.balanceOf(_bidder, derivativeTokenId), 0, "bidder balance");

        assertEq(_baseToken.balanceOf(_bidder), 0, "bidder balance");
    }

    function test_claimBid()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotIsConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
        givenBidIsClaimed(1)
    {
        // Check the bid
        (EncryptedMarginalPriceAuctionModule.Bid memory bid,) = _empaModule.getBid(_lotId, 1);
        assertEq(
            uint8(bid.status),
            uint8(EncryptedMarginalPriceAuctionModule.BidStatus.Claimed),
            "status"
        );

        uint256 derivativeTokenId =
            _linearVestingModule.computeId(address(_baseToken), abi.encode(_linearVestingParams));

        // Check the balances
        assertEq(_quoteToken.balanceOf(_bidder), 0, "quote token: bidder");

        assertEq(_baseToken.balanceOf(_bidder), 0, "base token: bidder");

        assertEq(
            _linearVestingModule.balanceOf(_bidder, derivativeTokenId),
            _BID_AMOUNT_OUT,
            "derivative: bidder"
        );

        assertEq(_linearVestingModule.redeemable(_bidder, derivativeTokenId), 0, "redeemable");
    }

    function test_claimBid_givenAfterVesting()
        external
        givenSellerHasBaseTokenBalance(_LOT_CAPACITY)
        givenSellerHasBaseTokenAllowance(_LOT_CAPACITY)
        givenAuctionTypeIsEMPA
        givenDerivativeTypeIsLinearVesting
        givenLotIsCreated
        givenLotHasStarted
        givenUserHasQuoteTokenBalance(_BID_AMOUNT)
        givenUserHasQuoteTokenAllowance(_BID_AMOUNT)
        givenBidIsCreated(_BID_AMOUNT, _BID_AMOUNT_OUT)
        givenLotIsConcluded
        givenPrivateKeyIsSubmitted
        givenLotIsDecrypted
        givenLotIsSettled
        givenBidIsClaimed(1)
    {
        // Warp to after vesting
        vm.warp(_VESTING_EXPIRY + 1);

        // Check the balances
        uint256 derivativeTokenId =
            _linearVestingModule.computeId(address(_baseToken), abi.encode(_linearVestingParams));
        assertEq(
            _linearVestingModule.balanceOf(_bidder, derivativeTokenId),
            _BID_AMOUNT_OUT,
            "bidder balance"
        );
        assertEq(
            _linearVestingModule.redeemable(_bidder, derivativeTokenId),
            _BID_AMOUNT_OUT,
            "redeemable"
        );
        assertEq(_baseToken.balanceOf(_bidder), 0, "bidder balance");

        // Redeem the derivative tokens
        vm.prank(_bidder);
        _linearVestingModule.redeemMax(derivativeTokenId);

        // Check the balances
        assertEq(_linearVestingModule.balanceOf(_bidder, derivativeTokenId), 0, "bidder balance");
        assertEq(_linearVestingModule.redeemable(_bidder, derivativeTokenId), 0, "redeemable");
        assertEq(_baseToken.balanceOf(_bidder), _BID_AMOUNT_OUT, "bidder balance");
    }
}
