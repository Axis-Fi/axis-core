// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Point, ECIES} from "src/lib/ECIES.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// Mocks
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockHook} from "test/modules/Auction/MockHook.sol";

// Auctions
import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";
import {Auction} from "src/modules/Auction.sol";
import {FeeManager} from "src/bases/FeeManager.sol";
import {AuctionHouse, Router} from "src/AuctionHouse.sol";

// Modules
import {Keycode, toKeycode, Veecode, keycodeFromVeecode} from "src/modules/Modules.sol";
import {EncryptedMarginalPriceAuctionModule} from "src/modules/auctions/EMPAM.sol";

abstract contract EmpaAuctionHouseTest is Test, Permit2User {
    uint96 internal constant _BASE_SCALE = 1e18;

    MockFeeOnTransferERC20 internal _baseToken;
    MockFeeOnTransferERC20 internal _quoteToken;
    MockDerivativeModule internal _mockDerivativeModule;
    Keycode internal _derivativeModuleKeycode;
    MockCondenserModule internal _mockCondenserModule;
    Keycode internal _condenserModuleKeycode;
    MockAllowlist internal _mockAllowlist;
    MockHook internal _mockHook;

    AuctionHouse internal _auctionHouse;
    EncryptedMarginalPriceAuctionModule internal _auctionModule;
    Keycode internal _auctionModuleKeycode;

    address internal _auctionOwner = address(0x1);
    address internal immutable _PROTOCOL = address(0x2);
    address internal immutable _CURATOR = address(0x3);
    address internal immutable _RECIPIENT = address(0x5);
    address internal immutable _REFERRER = address(0x6);

    address internal _bidder = address(0x4);
    uint256 internal _bidderKey;

    uint24 internal constant _CURATOR_MAX_FEE_PERCENT = 100;
    uint24 internal constant _CURATOR_FEE_PERCENT = 90;

    uint128 internal constant _BID_SEED = 12_345_678_901_234_567_890_123_456_789_012_345_678;
    uint256 internal constant _BID_PRIVATE_KEY = 112_233_445_566_778;
    Point internal _bidPublicKey;

    uint24 internal constant _PROTOCOL_FEE_PERCENT = 100;
    uint24 internal constant _REFERRER_FEE_PERCENT = 105;

    // Input to parameters
    uint48 internal _startTime;
    uint48 internal _duration = 1 days;
    uint24 internal constant _MIN_FILL_PERCENT = 25_000; // 25% = 2.5e18
    uint24 internal constant _MIN_BID_PERCENT = 1000; // 1% = 0.1e18

    /// @dev    Needs to be updated if the base token scale is changed
    uint96 internal constant _LOT_CAPACITY = 10e18;
    /// @dev    Needs to be updated if the base token scale is changed
    uint96 internal constant _MIN_PRICE = 2e18;
    uint256 internal _auctionPrivateKey;
    Point internal _auctionPublicKey;
    string internal constant _INFO_HASH = "info hash";

    /// @dev    Needs to be updated if the base token scale is changed
    uint96 internal _curatorMaxPotentialFee = _CURATOR_FEE_PERCENT * _LOT_CAPACITY / 1e5;
    /// @dev    Needs to be updated if the base token scale is changed
    uint96 internal _minBidSize = _LOT_CAPACITY * _MIN_BID_PERCENT / 1e5;
    uint96 internal constant _MIN_BID_SIZE = _LOT_CAPACITY * _MIN_BID_PERCENT / 1e5;

    // Parameters
    Auctioneer.RoutingParams internal _routingParams;
    Auction.AuctionParams internal _auctionParams;
    EncryptedMarginalPriceAuctionModule.AuctionDataParams internal _auctionDataParams;
    bytes internal _allowlistProof;
    bytes internal _permit2Data;
    uint256 internal _encryptedBidAmountOut;

    // Outputs
    uint96 internal _lotId = type(uint96).max; // Set to max to ensure it's not a valid lot id
    uint64 internal _bidId = type(uint64).max; // Set to max to ensure it's not a valid bid id

    function setUp() external {
        // Set block timestamp
        vm.warp(1_000_000);

        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", 18);
        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);

        _auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _PERMIT2_ADDRESS);

        _auctionModule = new EncryptedMarginalPriceAuctionModule(address(_auctionHouse));
        _auctionModuleKeycode = keycodeFromVeecode(_auctionModule.VEECODE());
        _auctionHouse.installModule(_auctionModule);

        _mockDerivativeModule = new MockDerivativeModule(address(_auctionHouse));
        _derivativeModuleKeycode = keycodeFromVeecode(_mockDerivativeModule.VEECODE());

        _mockCondenserModule = new MockCondenserModule(address(_auctionHouse));
        _condenserModuleKeycode = keycodeFromVeecode(_mockCondenserModule.VEECODE());

        _mockAllowlist = new MockAllowlist();
        _mockHook = new MockHook(address(_quoteToken), address(_baseToken));

        _auctionPrivateKey = 112_233_445_566;
        _auctionPublicKey = ECIES.calcPubKey(Point(1, 2), _auctionPrivateKey);
        _startTime = uint48(block.timestamp) + 1;

        _auctionDataParams = EncryptedMarginalPriceAuctionModule.AuctionDataParams({
            minPrice: _MIN_PRICE,
            minFillPercent: _MIN_FILL_PERCENT,
            minBidPercent: _MIN_BID_PERCENT,
            publicKey: _auctionPublicKey
        });

        _auctionParams = Auction.AuctionParams({
            start: _startTime,
            duration: _duration,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode(_auctionDataParams)
        });

        _routingParams = Auctioneer.RoutingParams({
            auctionType: _auctionModuleKeycode,
            baseToken: _baseToken,
            quoteToken: _quoteToken,
            curator: _CURATOR,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode("")
        });

        // Set the max curator fee
        _auctionHouse.setFee(
            _auctionModuleKeycode, FeeManager.FeeType.MaxCurator, _CURATOR_MAX_FEE_PERCENT
        );

        // Bids
        _bidPublicKey = ECIES.calcPubKey(Point(1, 2), _BID_PRIVATE_KEY);
        _bidderKey = _getRandomUint256();
        _bidder = vm.addr(_bidderKey);
    }

    // ===== Modifiers ===== //

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", decimals_);

        uint256 lotCapacity = _LOT_CAPACITY * 10 ** decimals_ / _BASE_SCALE;
        if (lotCapacity > type(uint96).max) revert("overflow");

        // Update dependent variables
        _minBidSize = uint96(lotCapacity * _MIN_BID_PERCENT / 1e5);

        // Update routing params
        _routingParams.baseToken = _baseToken;

        // Update auction params
        _auctionParams.capacity = uint96(lotCapacity);
    }

    modifier givenBaseTokenHasDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", decimals_);

        uint256 minPrice = _MIN_PRICE * 10 ** decimals_ / _BASE_SCALE;
        if (minPrice > type(uint96).max) revert("overflow");

        // Update routing params
        _routingParams.quoteToken = _quoteToken;

        // Update auction params
        _auctionDataParams.minPrice = uint96(minPrice);
        _auctionParams.implParams = abi.encode(_auctionDataParams);
    }

    modifier givenQuoteTokenHasDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
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

    modifier whenAllowlistIsSet() {
        // Update routing params
        _routingParams.allowlist = _mockAllowlist;
        _;
    }

    modifier whenHooksIsSet() {
        // Update routing params
        _routingParams.hooks = _mockHook;
        _;
    }

    modifier givenHookHasBaseTokenBalance(uint96 amount_) {
        uint96 amountScaled = _scaleBaseTokenAmount(amount_);

        // Mint the amount to the hook
        _baseToken.mint(address(_mockHook), amountScaled);
        _;
    }

    modifier givenAuctionModuleIsSunset() {
        _auctionHouse.sunsetModule(_auctionModuleKeycode);
        _;
    }

    modifier whenDerivativeModuleIsInstalled() {
        _auctionHouse.installModule(_mockDerivativeModule);
        _;
    }

    modifier whenDerivativeTypeIsSet() {
        _routingParams.derivativeType = toKeycode("DERV");
        _;
    }

    modifier whenCondenserModuleIsInstalled() {
        _auctionHouse.installModule(_mockCondenserModule);
        _;
    }

    modifier whenCondenserIsMapped() {
        _auctionHouse.setCondenser(
            _auctionModuleKeycode, _derivativeModuleKeycode, _condenserModuleKeycode
        );
        _;
    }

    modifier givenLotIsCreated() {
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
        _;
    }

    modifier givenOwnerHasBaseTokenAllowance(uint96 amount_) {
        uint96 amountScaled = _scaleBaseTokenAmount(amount_);

        // Approve the auction house
        vm.prank(_auctionOwner);
        _baseToken.approve(address(_auctionHouse), amountScaled);
        _;
    }

    modifier givenOwnerHasBaseTokenBalance(uint96 amount_) {
        uint96 amountScaled = _scaleBaseTokenAmount(amount_);

        // Mint the amount to the owner
        _baseToken.mint(_auctionOwner, amountScaled);
        _;
    }

    modifier givenBidderHasQuoteTokenBalance(uint96 amount_) {
        uint96 amountScale = _scaleQuoteTokenAmount(amount_);

        // Mint the amount to the bidder
        _quoteToken.mint(_bidder, amountScale);
        _;
    }

    modifier givenBidderHasQuoteTokenAllowance(uint96 amount_) {
        uint96 amountScale = _scaleQuoteTokenAmount(amount_);

        // Approve the auction house
        vm.prank(_bidder);
        _quoteToken.approve(address(_auctionHouse), amountScale);
        _;
    }

    modifier givenCuratorIsSet() {
        _routingParams.curator = _CURATOR;
        _;
    }

    modifier givenCuratorFeeIsSet() {
        vm.prank(_CURATOR);
        _auctionHouse.setCuratorFee(_auctionModuleKeycode, _CURATOR_FEE_PERCENT);
        _;
    }

    modifier givenCuratorHasApproved() {
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
        _;
    }

    function _createBid(uint96 amountIn_, uint96 amountOut_) internal {
        uint96 amountInScaled = _scaleQuoteTokenAmount(amountIn_);
        uint96 amountOutScaled = _scaleBaseTokenAmount(amountOut_);

        // Mint quote tokens to the bidder
        _quoteToken.mint(_bidder, amountInScaled);

        // Approve spending
        vm.prank(_bidder);
        _quoteToken.approve(address(_auctionHouse), amountInScaled);

        // Prepare amount out
        _encryptedBidAmountOut = _encryptBid(_lotId, _bidder, amountInScaled, amountOutScaled);

        // Prepare bid struct
        Router.BidParams memory bid = Router.BidParams({
            lotId: _lotId,
            referrer: _REFERRER,
            amount: amountInScaled,
            auctionData: abi.encode(_encryptedBidAmountOut, _bidPublicKey),
            allowlistProof: _allowlistProof,
            permit2Data: _permit2Data
        });

        // Bid
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(bid);
    }

    modifier givenBidIsCreated(uint96 amountIn_, uint96 amountOut_) {
        _createBid(amountIn_, amountOut_);
        _;
    }

    modifier givenLargeBidIsCreated(uint96 amountIn_, uint128 amountOut_) {
        uint96 amountInScaled = _scaleQuoteTokenAmount(amountIn_);
        uint128 amountOutScaled = uint128(amountOut_ * 10 ** (_baseToken.decimals()) / _BASE_SCALE);

        // Mint quote tokens to the bidder
        _quoteToken.mint(_bidder, amountInScaled);

        // Approve spending
        vm.prank(_bidder);
        _quoteToken.approve(address(_auctionHouse), amountInScaled);

        // Prepare amount out
        _encryptedBidAmountOut = _encryptBid(_lotId, _bidder, amountInScaled, amountOutScaled);

        // Prepare bid struct
        Router.BidParams memory bid = Router.BidParams({
            lotId: _lotId,
            referrer: _REFERRER,
            amount: amountInScaled,
            auctionData: abi.encode(_encryptedBidAmountOut, _bidPublicKey),
            allowlistProof: _allowlistProof,
            permit2Data: _permit2Data
        });

        // Bid
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(bid);
        _;
    }

    modifier givenBidIsRefunded(uint64 bidId_) {
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, bidId_);
        _;
    }

    modifier whenBidAmountOutIsEncrypted(uint96 amountIn_, uint96 amountOut_) {
        uint96 amountInScaled = _scaleQuoteTokenAmount(amountIn_);
        uint96 amountOutScaled = _scaleBaseTokenAmount(amountOut_);

        _encryptedBidAmountOut = _encryptBid(_lotId, _bidder, amountInScaled, amountOutScaled);
        _;
    }

    function _submitPrivateKey() internal {
        _auctionModule.submitPrivateKey(_lotId, _auctionPrivateKey, 0);
    }

    modifier givenPrivateKeyIsSubmitted() {
        _submitPrivateKey();
        _;
    }

    function _decryptLot() internal {
        EncryptedMarginalPriceAuctionModule.AuctionData memory bidData = _getBidData(_lotId);
        _auctionModule.decryptAndSortBids(_lotId, bidData.nextBidId - 1);
    }

    modifier givenLotIsDecrypted() {
        _decryptLot();
        _;
    }

    modifier givenLotIsSettled() {
        _auctionHouse.settle(_lotId);
        _;
    }

    function _concludeLot() internal {
        vm.warp(_startTime + _duration + 1);
    }

    modifier givenLotHasConcluded() {
        _concludeLot();
        _;
    }

    modifier givenLotHasStarted() {
        vm.warp(_auctionParams.start + 1);
        _;
    }

    modifier givenLotHasBeenCancelled() {
        vm.prank(_auctionOwner);
        _auctionHouse.cancel(_lotId);
        _;
    }

    modifier whenLotIdIsInvalid() {
        _lotId = 255;
        _;
    }

    modifier givenLotHasAllowlist() {
        _routingParams.allowlist = _mockAllowlist;
        _;
    }

    modifier givenBidderIsOnAllowlist(address bidder_, bytes memory proof_) {
        _mockAllowlist.setAllowedWithProof(bidder_, proof_, true);
        _;
    }

    modifier whenAllowlistProofIsIncorrect() {
        _allowlistProof = abi.encodePacked("incorrect proof");
        _;
    }

    modifier whenPermit2ApprovalIsProvided(uint96 amountIn_) {
        // Approve the Permit2 contract to spend the quote token
        vm.prank(_bidder);
        _quoteToken.approve(_PERMIT2_ADDRESS, type(uint256).max);

        // Set up the Permit2 approval
        uint48 deadline = uint48(block.timestamp);
        uint256 nonce = _getRandomUint256();
        bytes memory signature = _signPermit(
            address(_quoteToken), amountIn_, nonce, deadline, address(_auctionHouse), _bidderKey
        );

        Transfer.Permit2Approval memory _permit2Approval =
            Transfer.Permit2Approval({deadline: deadline, nonce: nonce, signature: signature});
        _permit2Data = abi.encode(_permit2Approval);
        _;
    }

    modifier givenProtocolFeeIsSet(uint24 fee_) {
        _auctionHouse.setFee(_auctionModuleKeycode, FeeManager.FeeType.Protocol, fee_);
        _;
    }

    modifier givenReferrerFeeIsSet(uint24 fee_) {
        _auctionHouse.setFee(_auctionModuleKeycode, FeeManager.FeeType.Referrer, fee_);
        _;
    }

    modifier givenBidIsClaimed(uint64 bidId_) {
        vm.prank(_bidder);
        _auctionHouse.claimBid(_lotId, bidId_);
        _;
    }

    // ===== Helper Functions ===== //

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

        Point memory sharedSecretKey = ECIES.calcPubKey(_bidPublicKey, _auctionPrivateKey);
        uint256 salt = uint256(keccak256(abi.encodePacked(lotId_, bidder_, amountIn_)));
        uint256 symmetricKey = uint256(keccak256(abi.encodePacked(sharedSecretKey.x, salt)));

        return formattedAmountOut ^ symmetricKey;
    }

    function _getLotRouting(uint96 lotId_) internal view returns (Auctioneer.Routing memory) {
        (
            Veecode auctionReference_,
            address owner_,
            ERC20 baseToken_,
            ERC20 quoteToken_,
            IHooks hooks_,
            IAllowlist allowlist_,
            Veecode derivativeReference_,
            bytes memory derivativeParams_,
            bool wrapDerivative_,
            uint256 prefunding_
        ) = _auctionHouse.lotRouting(lotId_);

        return Auctioneer.Routing({
            auctionReference: auctionReference_,
            owner: owner_,
            baseToken: baseToken_,
            quoteToken: quoteToken_,
            hooks: hooks_,
            allowlist: allowlist_,
            derivativeReference: derivativeReference_,
            derivativeParams: derivativeParams_,
            wrapDerivative: wrapDerivative_,
            prefunding: prefunding_
        });
    }

    function _getLotCuration(uint96 lotId_) internal view returns (Auctioneer.Curation memory) {
        (address curator_, bool curated_) = _auctionHouse.lotCuration(lotId_);

        return Auctioneer.Curation({curator: curator_, curated: curated_});
    }

    function _getLotData(uint96 lotId_) internal view returns (Auction.Lot memory) {
        (
            uint48 start_,
            uint48 conclusion_,
            uint8 quoteTokenDecimals_,
            uint8 baseTokenDecimals_,
            bool capacityInQuote_,
            uint96 capacity_,
            uint96 sold_,
            uint96 purchased_
        ) = _auctionModule.lotData(lotId_);

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

    function _getBidData(uint96 lotId_)
        internal
        view
        returns (EncryptedMarginalPriceAuctionModule.AuctionData memory)
    {
        (
            uint64 nextBidId,
            uint96 marginalPrice,
            uint96 minPrice,
            uint64 nextDecryptIndex,
            uint96 minFilled,
            uint96 minBidSize,
            Auction.Status status,
            Point memory publicKey,
            uint256 privateKey
        ) = _auctionModule.auctionData(lotId_);

        return EncryptedMarginalPriceAuctionModule.AuctionData({
            nextBidId: nextBidId,
            marginalPrice: marginalPrice,
            minPrice: minPrice,
            nextDecryptIndex: nextDecryptIndex,
            minFilled: minFilled,
            minBidSize: minBidSize,
            status: status,
            publicKey: publicKey,
            privateKey: privateKey,
            bidIds: new uint64[](0)
        });
    }

    function _getBid(
        uint96 lotId_,
        uint64 bidId_
    ) internal view returns (EncryptedMarginalPriceAuctionModule.Bid memory) {
        (
            address bidder,
            uint96 amountIn,
            uint96 minAmountOut,
            address referrer,
            EncryptedMarginalPriceAuctionModule.BidStatus status
        ) = _auctionModule.bids(lotId_, bidId_);

        return EncryptedMarginalPriceAuctionModule.Bid({
            bidder: bidder,
            amount: amountIn,
            minAmountOut: minAmountOut,
            referrer: referrer,
            status: status
        });
    }

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
        return _mulDivUp(amount_, uint96(10 ** (_quoteToken.decimals())), _BASE_SCALE);
    }

    function _scaleBaseTokenAmount(uint96 amount_) internal view returns (uint96) {
        return _mulDivUp(amount_, uint96(10 ** (_baseToken.decimals())), _BASE_SCALE);
    }
}
