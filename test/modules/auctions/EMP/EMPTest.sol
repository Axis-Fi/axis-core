// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Point, ECIES} from "src/lib/ECIES.sol";
import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";

// Mocks
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Modules
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/EMP.sol";

abstract contract EmpTest is Test, Permit2User {
    uint256 internal constant _BASE_SCALE = 1e18;

    address internal constant _PROTOCOL = address(0x2);
    address internal constant _BIDDER = address(0x3);
    address internal constant _REFERRER = address(0x4);

    uint256 internal constant _LOT_CAPACITY = 10e18;
    uint48 internal constant _DURATION = 1 days;
    uint256 internal constant _MIN_PRICE = 1e18;
    uint24 internal constant _MIN_FILL_PERCENT = 25_000; // 25%
    uint24 internal constant _MIN_BID_PERCENT = 40; // 0.04%
    /// @dev Re-calculated by _updateMinBidSize()
    uint256 internal _minBidSize;
    /// @dev Re-calculated by _updateMinBidAmount()
    uint256 internal _minBidAmount;

    uint256 internal constant _AUCTION_PRIVATE_KEY = 112_233_445_566;
    Point internal _auctionPublicKey;

    uint128 internal constant _BID_SEED = 12_345_678_901_234_567_890_123_456_789_012_345_678;
    uint256 internal constant _BID_PRIVATE_KEY = 112_233_445_566_778;
    Point internal _bidPublicKey;

    BatchAuctionHouse internal _auctionHouse;
    EncryptedMarginalPrice internal _module;

    // Input parameters (modifier via modifiers)
    uint48 internal _start;
    IAuction.AuctionParams internal _auctionParams;
    EncryptedMarginalPrice.AuctionDataParams internal _auctionDataParams;
    uint96 internal _lotId = type(uint96).max;
    uint64 internal _bidId = type(uint64).max;
    uint64[] internal _bidIds;

    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;

    bytes32 internal constant _QUEUE_START =
        bytes32(0x0000000000000000ffffffffffffffffffffffff000000000000000000000001);

    function setUp() public {
        vm.warp(1_000_000);

        _auctionHouse = new BatchAuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _module = new EncryptedMarginalPrice(address(_auctionHouse));

        _auctionPublicKey = ECIES.calcPubKey(Point(1, 2), _AUCTION_PRIVATE_KEY);
        _bidPublicKey = ECIES.calcPubKey(Point(1, 2), _BID_PRIVATE_KEY);

        _start = uint48(block.timestamp) + 1;

        _auctionDataParams = EncryptedMarginalPrice.AuctionDataParams({
            minPrice: _MIN_PRICE,
            minFillPercent: _MIN_FILL_PERCENT,
            minBidPercent: _MIN_BID_PERCENT,
            publicKey: _auctionPublicKey
        });

        _auctionParams = IAuction.AuctionParams({
            start: _start,
            duration: _DURATION,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode(_auctionDataParams)
        });

        _updateMinBidSize();
        _updateMinBidAmount();
    }

    // ======== Modifiers ======== //

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteTokenDecimals = decimals_;

        _auctionDataParams.minPrice = _scaleQuoteTokenAmount(_MIN_PRICE);

        _auctionParams.implParams = abi.encode(_auctionDataParams);

        _updateMinBidAmount();
    }

    modifier givenQuoteTokenDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
        _;
    }

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseTokenDecimals = decimals_;

        _auctionParams.capacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        _updateMinBidSize();
        _updateMinBidAmount();
    }

    modifier givenBaseTokenDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    modifier givenLotCapacity(uint256 capacity_) {
        _auctionParams.capacity = capacity_;

        _updateMinBidSize();
        _updateMinBidAmount();
        _;
    }

    modifier givenMinimumPrice(uint256 price_) {
        _auctionDataParams.minPrice = price_;

        _auctionParams.implParams = abi.encode(_auctionDataParams);

        _updateMinBidAmount();
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

    function _updateMinBidSize() internal {
        // Calculate the minimum bid size
        // Rounding consistent with EMPA
        _minBidSize = Math.fullMulDivUp(_auctionParams.capacity, _MIN_BID_PERCENT, 1e5);
    }

    function _updateMinBidAmount() internal {
        // Calculate the minimum bid amount
        // Rounding consistent with EMPA
        _minBidAmount =
            Math.fullMulDivUp(_minBidSize, _auctionDataParams.minPrice, 10 ** _baseTokenDecimals);
    }

    modifier givenMinimumBidPercentage(uint24 percentage_) {
        _auctionDataParams.minBidPercent = percentage_;

        _auctionParams.implParams = abi.encode(_auctionDataParams);

        _updateMinBidSize();
        _updateMinBidAmount();
        _;
    }

    modifier givenAuctionPublicKeyIsInvalid() {
        _auctionDataParams.publicKey = Point(0, 0);

        _auctionParams.implParams = abi.encode(_auctionDataParams);
        _;
    }

    function _createAuctionLot() internal {
        vm.prank(address(_auctionHouse));
        _module.auction(_lotId, _auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
    }

    modifier givenLotIsCreated() {
        _createAuctionLot();
        _;
    }

    function _cancelAuctionLot() internal {
        vm.prank(address(_auctionHouse));
        _module.cancelAuction(_lotId);
    }

    modifier givenLotIsCancelled() {
        _cancelAuctionLot();
        _;
    }

    function _formatBid(uint256 amountOut_) internal pure returns (uint256) {
        uint256 formattedAmountOut;
        {
            uint128 subtracted;
            unchecked {
                subtracted = uint128(amountOut_) - _BID_SEED;
            }
            formattedAmountOut = uint256(bytes32(abi.encodePacked(_BID_SEED, subtracted)));
        }

        return formattedAmountOut;
    }

    function _encryptBid(
        uint96 lotId_,
        address bidder_,
        uint256 amountIn_,
        uint256 amountOut_,
        uint256 bidPrivateKey_
    ) internal view returns (uint256) {
        // Format the amount out
        uint256 formattedAmountOut = _formatBid(amountOut_);

        Point memory sharedSecretKey = ECIES.calcPubKey(_auctionPublicKey, bidPrivateKey_);
        uint256 salt = uint256(keccak256(abi.encodePacked(lotId_, bidder_, uint96(amountIn_))));
        uint256 symmetricKey = uint256(keccak256(abi.encodePacked(sharedSecretKey.x, salt)));

        return formattedAmountOut ^ symmetricKey;
    }

    function _encryptBid(
        uint96 lotId_,
        address bidder_,
        uint256 amountIn_,
        uint256 amountOut_
    ) internal view returns (uint256) {
        return _encryptBid(lotId_, bidder_, amountIn_, amountOut_, _BID_PRIVATE_KEY);
    }

    function _createBidData(
        address bidder_,
        uint256 amountIn_,
        uint256 amountOut_
    ) internal view returns (bytes memory) {
        uint256 encryptedAmountOut = _encryptBid(_lotId, bidder_, amountIn_, amountOut_);

        return abi.encode(encryptedAmountOut, _bidPublicKey);
    }

    function _createBidData(
        uint256 amountIn_,
        uint256 amountOut_
    ) internal view returns (bytes memory) {
        return _createBidData(_BIDDER, amountIn_, amountOut_);
    }

    function _createBid(
        address bidder_,
        uint256 amountIn_,
        uint256 amountOut_
    ) internal returns (uint64 bidId) {
        bytes memory bidData = _createBidData(bidder_, amountIn_, amountOut_);

        vm.prank(address(_auctionHouse));
        bidId = _module.bid(_lotId, bidder_, _REFERRER, amountIn_, bidData);
        _bidIds.push(bidId);

        return bidId;
    }

    function _createBid(uint256 amountIn_, uint256 amountOut_) internal returns (uint64 bidId) {
        return _createBid(_BIDDER, amountIn_, amountOut_);
    }

    modifier givenBidIsCreated(uint256 amountIn_, uint256 amountOut_) {
        _bidId = _createBid(amountIn_, amountOut_);
        _;
    }

    modifier givenBidIsRefunded(uint64 bidId_) {
        // Find bid index

        // Get number of bids from module
        uint256 numBids = _module.getNumBids(_lotId);

        // Retrieve bid IDs from the module
        uint64[] memory bidIds = _module.getBidIds(_lotId, 0, numBids);

        // Iterate through them to find the index of the bid
        uint256 index = type(uint256).max;

        uint256 len = bidIds.length;
        for (uint256 i = 0; i < len; i++) {
            if (bidIds[i] == bidId_) {
                index = i;
                break;
            }
        }

        vm.prank(address(_auctionHouse));
        _module.refundBid(_lotId, bidId_, index, _BIDDER);
        _;
    }

    modifier givenBidIsClaimed(uint64 bidId_) {
        uint64[] memory bidIds = new uint64[](1);
        bidIds[0] = bidId_;

        vm.prank(address(_auctionHouse));
        _module.claimBids(_lotId, bidIds);
        _;
    }

    function _submitPrivateKey() internal {
        _module.submitPrivateKey(_lotId, _AUCTION_PRIVATE_KEY, 0, new bytes32[](0));
    }

    modifier givenPrivateKeyIsSubmitted() {
        _submitPrivateKey();
        _;
    }

    function _decryptLot() internal {
        EncryptedMarginalPrice.AuctionData memory auctionData = _getAuctionData(_lotId);
        uint256 numBids = auctionData.nextBidId - 1;
        bytes32[] memory hints = new bytes32[](100);
        for (uint256 i = 0; i < 100; i++) {
            hints[i] = bytes32(0x0000000000000000ffffffffffffffffffffffff000000000000000000000001);
        }
        while (numBids > 0) {
            uint256 gasStart = gasleft();
            _module.decryptAndSortBids(_lotId, 100, hints);
            console2.log("Gas used for decrypts: ", gasStart - gasleft());
            if (numBids > 100) {
                numBids -= 100;
            } else {
                numBids = 0;
            }
        }
    }

    modifier givenLotIsDecrypted() {
        _decryptLot();
        _;
    }

    function _settleLot() internal {
        vm.prank(address(_auctionHouse));
        _module.settle(_lotId, 100_000);
    }

    modifier givenLotIsSettled() {
        _settleLot();
        _;
    }

    function _concludeLot() internal {
        vm.warp(_start + _DURATION + 1);
    }

    modifier givenLotHasConcluded() {
        _concludeLot();
        _;
    }

    modifier givenLotHasStarted() {
        vm.warp(_start + 1);
        _;
    }

    modifier givenLotSettlePeriodHasPassed() {
        vm.warp(_start + _DURATION + 6 hours);
        _;
    }

    modifier givenLotProceedsAreClaimed() {
        vm.prank(address(_auctionHouse));
        _module.claimProceeds(_lotId);
        _;
    }

    // ======== Internal Functions ======== //

    function _scaleQuoteTokenAmount(uint256 amount_) internal view returns (uint256) {
        return Math.fullMulDiv(amount_, 10 ** _quoteTokenDecimals, _BASE_SCALE);
    }

    function _scaleBaseTokenAmount(uint256 amount_) internal view returns (uint256) {
        return Math.fullMulDiv(amount_, 10 ** _baseTokenDecimals, _BASE_SCALE);
    }

    function _getAuctionData(uint96 lotId_)
        internal
        view
        returns (EncryptedMarginalPrice.AuctionData memory)
    {
        (
            uint64 nextBidId_,
            uint64 nextDecryptIndex_,
            EncryptedMarginalPrice.LotStatus status_,
            uint64 marginalBidId_,
            bool proceedsClaimed_,
            uint256 marginalPrice_,
            uint256 minPrice_,
            uint256 minFilled_,
            uint256 minBidSize_,
            Point memory publicKey_,
            uint256 privateKey_
        ) = _module.auctionData(lotId_);

        return EncryptedMarginalPrice.AuctionData({
            nextBidId: nextBidId_,
            nextDecryptIndex: nextDecryptIndex_,
            status: status_,
            marginalBidId: marginalBidId_,
            proceedsClaimed: proceedsClaimed_,
            marginalPrice: marginalPrice_,
            minFilled: minFilled_,
            minBidSize: minBidSize_,
            minPrice: minPrice_,
            publicKey: publicKey_,
            privateKey: privateKey_,
            bidIds: new uint64[](0)
        });
    }

    function _getAuctionLot(uint96 lotId_) internal view returns (IAuction.Lot memory) {
        return _module.getLot(lotId_);
    }

    function _getPartialFill(uint96 lotId_)
        internal
        view
        returns (EncryptedMarginalPrice.PartialFill memory)
    {
        return _module.getPartialFill(lotId_);
    }

    function _getBid(
        uint96 lotId_,
        uint64 bidId_
    ) internal view returns (EncryptedMarginalPrice.Bid memory) {
        (
            address bidder_,
            uint96 amount_,
            uint96 minAmountOut_,
            address referrer_,
            EncryptedMarginalPrice.BidStatus status_
        ) = _module.bids(lotId_, bidId_);

        return EncryptedMarginalPrice.Bid({
            bidder: bidder_,
            amount: amount_,
            minAmountOut: minAmountOut_,
            referrer: referrer_,
            status: status_
        });
    }

    function _getEncryptedBid(
        uint96 lotId_,
        uint64 bidId_
    ) internal view returns (EncryptedMarginalPrice.EncryptedBid memory) {
        (uint256 encryptedAmountOut_, Point memory publicKey_) =
            _module.encryptedBids(lotId_, bidId_);

        return EncryptedMarginalPrice.EncryptedBid({
            encryptedAmountOut: encryptedAmountOut_,
            bidPubKey: publicKey_
        });
    }
}
