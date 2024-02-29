// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {Point, ECIES} from "src/lib/ECIES.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// Mocks
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Modules
import {AuctionHouse} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

abstract contract EmpaModuleTest is Test, Permit2User {
    uint96 internal constant _BASE_SCALE = 1e18;

    address internal constant _PROTOCOL = address(0x2);
    address internal constant _BIDDER = address(0x3);
    address internal constant _REFERRER = address(0x4);

    uint96 internal constant _LOT_CAPACITY = 10e18;
    uint48 internal constant _DURATION = 1 days;
    uint96 internal constant _MIN_PRICE = 1e18;
    uint24 internal constant _MIN_FILL_PERCENT = 25_000; // 25%
    uint24 internal constant _MIN_BID_PERCENT = 1000; // 1%

    uint256 internal constant _AUCTION_PRIVATE_KEY = 112_233_445_566;
    Point internal _auctionPublicKey;

    uint128 internal constant _BID_SEED = 12_345_678_901_234_567_890_123_456_789_012_345_678;
    uint256 internal constant _BID_PRIVATE_KEY = 112_233_445_566_778;
    Point internal _bidPublicKey;

    AuctionHouse internal _auctionHouse;
    EncryptedMarginalPriceAuctionModule internal _module;

    // Input parameters (modifier via modifiers)
    uint48 internal _start;
    Auction.AuctionParams internal _auctionParams;
    EncryptedMarginalPriceAuctionModule.AuctionDataParams internal _auctionDataParams;
    uint96 internal _lotId = 2;
    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;

    function setUp() public {
        vm.warp(1_000_000);

        _auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _PERMIT2_ADDRESS);
        _module = new EncryptedMarginalPriceAuctionModule(address(_auctionHouse));

        _auctionPublicKey = ECIES.calcPubKey(Point(1, 2), _AUCTION_PRIVATE_KEY);
        _bidPublicKey = ECIES.calcPubKey(Point(1, 2), _BID_PRIVATE_KEY);

        _start = uint48(block.timestamp) + 1;

        _auctionDataParams = EncryptedMarginalPriceAuctionModule.AuctionDataParams({
            minPrice: _MIN_PRICE,
            minFillPercent: _MIN_FILL_PERCENT,
            minBidPercent: _MIN_BID_PERCENT,
            publicKey: _auctionPublicKey
        });

        _auctionParams = Auction.AuctionParams({
            start: _start,
            duration: _DURATION,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode(_auctionDataParams)
        });
    }

    // ======== Modifiers ======== //

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteTokenDecimals = decimals_;

        _auctionDataParams.minPrice = _scaleQuoteTokenAmount(_MIN_PRICE);

        _auctionParams.implParams = abi.encode(_auctionDataParams);
    }

    modifier givenQuoteTokenDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
        _;
    }

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseTokenDecimals = decimals_;

        _auctionParams.capacity = _scaleBaseTokenAmount(_LOT_CAPACITY);
    }

    modifier givenBaseTokenDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    modifier givenLotCapacity(uint96 capacity_) {
        _auctionParams.capacity = capacity_;
        _;
    }

    modifier givenMinimumPrice(uint96 price_) {
        _auctionDataParams.minPrice = price_;

        _auctionParams.implParams = abi.encode(_auctionDataParams);
        _;
    }

    modifier givenStartTimestamp(uint48 start_) {
        _auctionParams.start = start_;
        _;
    }

    modifier givenDuration(uint48 duration_) {
        _auctionParams.duration = duration_;
        _;
    }

    modifier givenMinimumFillPercentage(uint24 percentage_) {
        _auctionDataParams.minFillPercent = percentage_;

        _auctionParams.implParams = abi.encode(_auctionDataParams);
        _;
    }

    modifier givenMinimumBidPercentage(uint24 percentage_) {
        _auctionDataParams.minBidPercent = percentage_;

        _auctionParams.implParams = abi.encode(_auctionDataParams);
        _;
    }

    modifier givenAuctionPublicKeyIsInvalid() {
        _auctionDataParams.publicKey = Point(0, 0);

        _auctionParams.implParams = abi.encode(_auctionDataParams);
        _;
    }

    function _createAuctionLot() internal returns (bool prefundingRequired, uint256 capacity) {
        vm.prank(address(_auctionHouse));
        return _module.auction(_lotId, _auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
    }

    modifier givenLotIsCreated() {
        _createAuctionLot();
        _;
    }

    modifier givenLotHasBeenCancelled() {
        vm.prank(address(_auctionHouse));
        _module.cancelAuction(_lotId);
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
        uint128 amountOut_
    ) internal view returns (uint256) {
        // Format the amount out
        uint256 formattedAmountOut = _formatBid(amountOut_);

        Point memory sharedSecretKey = ECIES.calcPubKey(_bidPublicKey, _AUCTION_PRIVATE_KEY); // TODO is the use of the private key here correct?
        uint256 salt = uint256(keccak256(abi.encodePacked(lotId_, bidder_, amountIn_)));
        uint256 symmetricKey = uint256(keccak256(abi.encodePacked(sharedSecretKey.x, salt)));

        return formattedAmountOut ^ symmetricKey;
    }

    function _createBid(uint96 amountIn_, uint96 amountOut_) internal returns (uint64 bidId) {
        uint256 encryptedAmountOut = _encryptBid(_lotId, _BIDDER, amountIn_, amountOut_);

        bytes memory bidData = abi.encode(encryptedAmountOut, _bidPublicKey);

        vm.prank(address(_auctionHouse));
        return _module.bid(_lotId, _BIDDER, _REFERRER, amountIn_, bidData);
    }

    modifier givenBidIsCreated(uint96 amountIn_, uint96 amountOut_) {
        _createBid(amountIn_, amountOut_);
        _;
    }

    modifier givenBidIsRefunded(uint64 bidId_) {
        vm.prank(_BIDDER);
        _module.refundBid(_lotId, bidId_, _BIDDER);
        _;
    }

    modifier givenBidIsClaimed(uint64 bidId_) {
        vm.prank(_BIDDER);
        _module.claimBid(_lotId, bidId_, _BIDDER);
        _;
    }

    function _submitPrivateKey() internal {
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0);
    }

    modifier givenPrivateKeyIsSubmitted() {
        _submitPrivateKey();
        _;
    }

    function _decryptLot() internal {
        EncryptedMarginalPriceAuctionModule.AuctionData memory auctionData = _getAuctionData(_lotId);
        _module.decryptAndSortBids(_lotId, auctionData.nextBidId - 1);
    }

    modifier givenLotIsDecrypted() {
        _decryptLot();
        _;
    }

    modifier givenLotIsSettled() {
        _module.settle(_lotId);
        _;
    }

    modifier givenLotHasConcluded() {
        vm.warp(_start + _DURATION + 1);
        _;
    }

    modifier givenLotHasStarted() {
        vm.warp(_start + 1);
        _;
    }

    // ======== Internal Functions ======== //

    function _mulDivUp(uint96 mul1_, uint96 mul2_, uint96 div_) internal pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivUp(mul1_, mul2_, div_);
        if (product > type(uint96).max) revert("overflow");

        return uint96(product);
    }

    function _mulDivDown(uint96 mul1_, uint96 mul2_, uint96 div_) internal pure returns (uint96) {
        uint256 product = FixedPointMathLib.mulDivDown(mul1_, mul2_, div_);
        if (product > type(uint96).max) revert("overflow");

        return uint96(product);
    }

    function _scaleQuoteTokenAmount(uint96 amount_) internal view returns (uint96) {
        return _mulDivUp(amount_, uint96(10 ** _quoteTokenDecimals), _BASE_SCALE);
    }

    function _scaleBaseTokenAmount(uint96 amount_) internal view returns (uint96) {
        return _mulDivUp(amount_, uint96(10 ** _baseTokenDecimals), _BASE_SCALE);
    }

    function _getAuctionData(uint96 lotId_)
        internal
        view
        returns (EncryptedMarginalPriceAuctionModule.AuctionData memory)
    {
        (
            uint64 nextBidId_,
            uint96 marginalPrice_,
            uint96 minPrice_,
            uint64 nextDecryptIndex_,
            uint96 minFilled_,
            uint96 minBidSize_,
            Auction.Status status_,
            Point memory publicKey_,
            uint256 privateKey_
        ) = _module.auctionData(lotId_);

        return EncryptedMarginalPriceAuctionModule.AuctionData({
            nextBidId: nextBidId_,
            marginalPrice: marginalPrice_,
            minPrice: minPrice_,
            nextDecryptIndex: nextDecryptIndex_,
            minFilled: minFilled_,
            minBidSize: minBidSize_,
            status: status_,
            publicKey: publicKey_,
            privateKey: privateKey_,
            bidIds: new uint64[](0)
        });
    }

    function _getAuctionLot(uint96 lotId_) internal view returns (Auction.Lot memory) {
        (
            uint48 start_,
            uint48 conclusion_,
            uint8 quoteTokenDecimals_,
            uint8 baseTokenDecimals_,
            bool capacityInQuote_,
            uint96 capacity_,
            uint96 sold_,
            uint96 purchased_
        ) = _module.lotData(lotId_);

        return Auction.Lot({
            start: start_,
            conclusion: conclusion_,
            quoteTokenDecimals: quoteTokenDecimals_,
            baseTokenDecimals: baseTokenDecimals_,
            capacityInQuote: capacityInQuote_,
            capacity: capacity_,
            sold: sold_,
            purchased: purchased_
        });
    }
}
