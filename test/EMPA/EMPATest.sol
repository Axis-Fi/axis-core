// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Point, ECIES} from "src/lib/ECIES.sol";
import {Transfer} from "src/lib/Transfer.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockEMPAHook} from "test/EMPA/mocks/MockEMPAHook.sol";

// Auctions
import {IHooks} from "src/interfaces/IHooks.sol";
import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {EncryptedMarginalPriceAuction, FeeManager} from "src/EMPA.sol";

// Modules
import {toKeycode, Veecode} from "src/modules/Modules.sol";

import {console2} from "forge-std/console2.sol";

abstract contract EmpaTest is Test, Permit2User {
    MockFeeOnTransferERC20 internal _baseToken;
    MockERC20 internal _quoteToken;
    MockDerivativeModule internal _mockDerivativeModule;
    MockAllowlist internal _mockAllowlist;
    MockEMPAHook internal _mockHook;

    EncryptedMarginalPriceAuction internal _auctionHouse;

    address internal _auctionOwner = address(0x1);
    address internal immutable _PROTOCOL = address(0x2);
    address internal immutable _CURATOR = address(0x3);
    address internal immutable _RECIPIENT = address(0x5);
    address internal immutable _REFERRER = address(0x6);

    address internal _bidder = address(0x4);
    uint256 internal _bidderKey;

    uint24 internal constant _CURATOR_MAX_FEE_PERCENT = 100;
    uint24 internal constant _CURATOR_FEE_PERCENT = 90;

    uint128 internal constant _BID_SEED = 123_456;
    uint256 internal constant _BID_PRIVATE_KEY = 112_233_445_566_778;
    Point internal _bidPublicKey;

    uint24 internal constant _PROTOCOL_FEE = 100;
    uint24 internal constant _REFERRER_FEE = 105;

    // Input to parameters
    uint48 internal _startTime;
    uint48 internal _duration = 1 days;
    uint24 internal constant _MIN_FILL_PERCENT = 1000;
    uint24 internal constant _MIN_BID_PERCENT = 100;
    uint96 internal constant _LOT_CAPACITY = 10e18;
    uint96 internal constant _MIN_PRICE = 2e18;
    uint256 internal _auctionPrivateKey;
    Point internal _auctionPublicKey;
    string internal constant _INFO_HASH = "info hash";
    uint96 internal _curatorMaxPotentialFee = _CURATOR_FEE_PERCENT * _LOT_CAPACITY / 1e5;

    // Parameters
    EncryptedMarginalPriceAuction.RoutingParams internal _routingParams;
    EncryptedMarginalPriceAuction.AuctionParams internal _auctionParams;
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
        _quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        _auctionHouse =
            new EncryptedMarginalPriceAuction(address(this), _PROTOCOL, _PERMIT2_ADDRESS);
        _mockDerivativeModule = new MockDerivativeModule(address(_auctionHouse));
        _mockAllowlist = new MockAllowlist();
        _mockHook = new MockEMPAHook(address(_quoteToken), address(_baseToken));

        _auctionPrivateKey = 112_233_445_566;
        _auctionPublicKey = ECIES.calcPubKey(Point(1, 2), bytes32(_auctionPrivateKey));
        _startTime = uint48(block.timestamp) + 1;

        _auctionParams = EncryptedMarginalPriceAuction.AuctionParams({
            start: _startTime,
            duration: _duration,
            minFillPercent: _MIN_FILL_PERCENT,
            minBidPercent: _MIN_BID_PERCENT,
            capacity: _LOT_CAPACITY,
            minimumPrice: _MIN_PRICE,
            publicKey: _auctionPublicKey
        });

        _routingParams = EncryptedMarginalPriceAuction.RoutingParams({
            baseToken: _baseToken,
            quoteToken: _quoteToken,
            curator: _CURATOR,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            wrapDerivative: false,
            derivativeParams: abi.encode("")
        });

        // Set the max curator fee
        _auctionHouse.setFee(FeeManager.FeeType.MaxCurator, _CURATOR_MAX_FEE_PERCENT);

        // Bids
        _bidPublicKey = ECIES.calcPubKey(Point(1, 2), bytes32(_BID_PRIVATE_KEY));
        _bidderKey = _getRandomUint256();
        _bidder = vm.addr(_bidderKey);
    }

    // ===== Modifiers ===== //

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", decimals_);

        // Update routing params
        _routingParams.baseToken = _baseToken;
    }

    modifier givenBaseTokenHasDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", decimals_);

        // Update routing params
        _routingParams.quoteToken = _quoteToken;
    }

    modifier givenQuoteTokenHasDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
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

    modifier givenHookHasBaseTokenBalance(uint256 amount_) {
        // Mint the amount to the hook
        _baseToken.mint(address(_mockHook), amount_);
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

    modifier givenLotIsCreated() {
        vm.prank(_auctionOwner);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
        _;
    }

    modifier givenOwnerHasBaseTokenAllowance(uint256 amount_) {
        // Approve the auction house
        vm.prank(_auctionOwner);
        _baseToken.approve(address(_auctionHouse), amount_);
        _;
    }

    modifier givenOwnerHasBaseTokenBalance(uint256 amount_) {
        // Mint the amount to the owner
        _baseToken.mint(_auctionOwner, amount_);
        _;
    }

    modifier givenBidderHasQuoteTokenBalance(uint256 amount_) {
        // Mint the amount to the bidder
        _quoteToken.mint(_bidder, amount_);
        _;
    }

    modifier givenBidderHasQuoteTokenAllowance(uint256 amount_) {
        // Approve the auction house
        vm.prank(_bidder);
        _quoteToken.approve(address(_auctionHouse), amount_);
        _;
    }

    modifier givenCuratorIsSet() {
        _routingParams.curator = _CURATOR;
        _;
    }

    modifier givenCuratorFeeIsSet() {
        vm.prank(_CURATOR);
        _auctionHouse.setCuratorFee(_CURATOR_FEE_PERCENT);
        _;
    }

    modifier givenCuratorHasApproved() {
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
        _;
    }

    modifier givenBidIsCreated(uint96 amountIn_, uint96 amountOut_) {
        // Mint quote tokens to the bidder
        _quoteToken.mint(_bidder, amountIn_);

        // Approve spending
        vm.prank(_bidder);
        _quoteToken.approve(address(_auctionHouse), amountIn_);

        // Prepare amount out
        _encryptedBidAmountOut = _encryptBid(_lotId, _bidder, amountIn_, amountOut_);

        // Bid
        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(
            _lotId,
            _REFERRER,
            amountIn_,
            _encryptedBidAmountOut,
            _bidPublicKey,
            bytes(""),
            bytes("")
        );
        _;
    }

    modifier givenBidIsRefunded(uint64 bidId_) {
        vm.prank(_bidder);
        _auctionHouse.refundBid(_lotId, bidId_);
        _;
    }

    modifier whenBidAmountOutIsEncrypted(uint96 amountIn_, uint96 amountOut_) {
        _encryptedBidAmountOut = _encryptBid(_lotId, _bidder, amountIn_, amountOut_);
        _;
    }

    modifier givenPrivateKeyIsSubmitted() {
        _auctionHouse.submitPrivateKey(_lotId, bytes32(_auctionPrivateKey));
        _;
    }

    modifier givenLotIsDecrypted() {
        // Get the number of bids
        EncryptedMarginalPriceAuction.BidData memory bidData = _getBidData(_lotId);

        _auctionHouse.decryptAndSortBids(_lotId, bidData.nextBidId - 1);
        _;
    }

    modifier givenLotIsSettled() {
        _auctionHouse.settle(_lotId);
        _;
    }

    modifier givenLotHasConcluded() {
        vm.warp(_startTime + _duration + 1);
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
        _auctionHouse.setFee(FeeManager.FeeType.Protocol, fee_);
        _;
    }

    modifier givenReferrerFeeIsSet(uint24 fee_) {
        _auctionHouse.setFee(FeeManager.FeeType.Referrer, fee_);
        _;
    }

    // ===== Helper Functions ===== //

    function _encryptBid(
        uint96 lotId_,
        address bidder_,
        uint96 amountIn_,
        uint96 amountOut_
    ) internal view returns (uint256) {
        // Format the amount out
        uint256 formattedAmountOut;
        {
            uint128 subtracted;
            unchecked {
                subtracted = _BID_SEED - amountOut_;
            }
            formattedAmountOut = uint256(bytes32(abi.encodePacked(_BID_SEED, subtracted)));
        }
        console2.log("formattedAmountOut", formattedAmountOut);

        Point memory sharedSecretKey = ECIES.calcPubKey(_bidPublicKey, bytes32(_auctionPrivateKey));
        bytes32 salt = keccak256(abi.encodePacked(lotId_, bidder_, amountIn_));
        uint256 symmetricKey = uint256(keccak256(abi.encodePacked(sharedSecretKey.x, salt)));

        return formattedAmountOut ^ symmetricKey;
    }

    function _getLotRouting(uint96 lotId_)
        internal
        view
        returns (EncryptedMarginalPriceAuction.Routing memory)
    {
        (
            address owner_,
            ERC20 baseToken_,
            ERC20 quoteToken_,
            address curator_,
            uint96 curatorFee_,
            bool curated_,
            IHooks hooks_,
            IAllowlist allowlist_,
            Veecode derivativeRef_,
            bool wrapDerivative_,
            bytes memory derivativeParams_
        ) = _auctionHouse.lotRouting(lotId_);

        return EncryptedMarginalPriceAuction.Routing({
            owner: owner_,
            baseToken: baseToken_,
            quoteToken: quoteToken_,
            curator: curator_,
            curatorFee: curatorFee_,
            curated: curated_,
            hooks: hooks_,
            allowlist: allowlist_,
            derivativeReference: derivativeRef_,
            wrapDerivative: wrapDerivative_,
            derivativeParams: derivativeParams_
        });
    }

    function _getLotData(uint96 lotId_)
        internal
        view
        returns (EncryptedMarginalPriceAuction.Lot memory)
    {
        (
            uint96 minimumPrice_,
            uint96 capacity_,
            uint8 quoteTokenDecimals_,
            uint8 baseTokenDecimals_,
            uint48 start_,
            uint48 conclusion_,
            EncryptedMarginalPriceAuction.AuctionStatus status_,
            uint96 minFilled_,
            uint96 minBidSize_
        ) = _auctionHouse.lotData(lotId_);

        return EncryptedMarginalPriceAuction.Lot({
            minimumPrice: minimumPrice_,
            capacity: capacity_,
            quoteTokenDecimals: quoteTokenDecimals_,
            baseTokenDecimals: baseTokenDecimals_,
            start: start_,
            conclusion: conclusion_,
            status: status_,
            minFilled: minFilled_,
            minBidSize: minBidSize_
        });
    }

    function _getBidData(uint96 lotId_)
        internal
        view
        returns (EncryptedMarginalPriceAuction.BidData memory)
    {
        (
            uint64 nextBidId,
            uint64 nextDecryptIndex,
            uint96 marginalPrice,
            Point memory publicKey,
            bytes32 privateKey
        ) = _auctionHouse.bidData(lotId_);

        return EncryptedMarginalPriceAuction.BidData({
            nextBidId: nextBidId,
            nextDecryptIndex: nextDecryptIndex,
            marginalPrice: marginalPrice,
            publicKey: publicKey,
            privateKey: privateKey,
            bidIds: new uint64[](0)
        });
    }

    function _getBid(
        uint96 lotId_,
        uint64 bidId_
    ) internal view returns (EncryptedMarginalPriceAuction.Bid memory) {
        (
            address bidder,
            uint96 amountIn,
            uint96 minAmountOut,
            address referrer,
            EncryptedMarginalPriceAuction.BidStatus status
        ) = _auctionHouse.bids(lotId_, bidId_);

        return EncryptedMarginalPriceAuction.Bid({
            bidder: bidder,
            amount: amountIn,
            minAmountOut: minAmountOut,
            referrer: referrer,
            status: status
        });
    }
}