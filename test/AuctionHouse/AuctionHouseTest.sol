// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// Mocks
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockBatchAuctionModule} from "test/modules/Auction/MockBatchAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {MockHook} from "test/modules/Auction/MockHook.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";

// Auctions
import {AuctionHouse, Router} from "src/AuctionHouse.sol";
import {Auction, AuctionModule} from "src/modules/Auction.sol";
import {FeeManager} from "src/bases/FeeManager.sol";
import {IHooks, IAllowlist, Auctioneer} from "src/bases/Auctioneer.sol";
import {Catalogue} from "src/Catalogue.sol";

import {Veecode, toKeycode, keycodeFromVeecode, Keycode} from "src/modules/Modules.sol";

abstract contract AuctionHouseTest is Test, Permit2User {
    MockFeeOnTransferERC20 internal _baseToken;
    MockFeeOnTransferERC20 internal _quoteToken;

    AuctionHouse internal _auctionHouse;
    AuctionModule internal _auctionModule;
    Keycode internal _auctionModuleKeycode;
    Catalogue internal _catalogue;

    MockAtomicAuctionModule internal _atomicAuctionModule;
    Keycode internal _atomicAuctionModuleKeycode;
    MockBatchAuctionModule internal _batchAuctionModule;
    Keycode internal _batchAuctionModuleKeycode;
    MockDerivativeModule internal _derivativeModule;
    Keycode internal _derivativeModuleKeycode;
    MockCondenserModule internal _condenserModule;
    Keycode internal _condenserModuleKeycode;
    MockAllowlist internal _allowlist;
    MockHook internal _hook;

    uint96 internal constant _BASE_SCALE = 1e18;

    address internal constant _SELLER = address(0x1);
    address internal constant _PROTOCOL = address(0x2);
    address internal constant _CURATOR = address(0x3);
    address internal constant _RECIPIENT = address(0x5);
    address internal constant _REFERRER = address(0x6);

    address internal _bidder = address(0x4);
    uint256 internal _bidderKey;

    uint24 internal constant _CURATOR_MAX_FEE_PERCENT = 100;
    uint24 internal constant _CURATOR_FEE_PERCENT = 90;
    uint24 internal _curatorFeePercentActual;

    uint24 internal constant _PROTOCOL_FEE_PERCENT = 100;
    uint24 internal constant _REFERRER_FEE_PERCENT = 105;
    uint24 internal _protocolFeePercentActual;
    uint24 internal _referrerFeePercentActual;

    uint96 internal _curatorMaxPotentialFee;
    bool internal _curatorApproved;

    // Input to parameters
    uint48 internal _startTime;
    uint48 internal _duration = 1 days;
    /// @dev    Needs to be updated if the base token scale is changed
    uint96 internal constant _LOT_CAPACITY = 10e18;
    string internal constant _INFO_HASH = "info hash";
    bytes internal _derivativeParams = abi.encode("");

    // Parameters
    Auctioneer.RoutingParams internal _routingParams;
    Auction.AuctionParams internal _auctionParams;
    bytes internal _allowlistProof;
    bytes internal _permit2Data;

    // Outputs
    uint96 internal _lotId = type(uint96).max; // Set to max to ensure it's not a valid lot id
    uint64 internal _bidId = type(uint64).max; // Set to max to ensure it's not a valid bid id

    function setUp() public {
        // Set block timestamp
        vm.warp(1_000_000);

        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", 18);
        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);

        _auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _PERMIT2_ADDRESS);
        _catalogue = new Catalogue(address(_auctionHouse));

        _atomicAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));
        _atomicAuctionModuleKeycode = keycodeFromVeecode(_atomicAuctionModule.VEECODE());
        _batchAuctionModule = new MockBatchAuctionModule(address(_auctionHouse));
        _batchAuctionModuleKeycode = keycodeFromVeecode(_batchAuctionModule.VEECODE());
        _derivativeModule = new MockDerivativeModule(address(_auctionHouse));
        _derivativeModuleKeycode = keycodeFromVeecode(_derivativeModule.VEECODE());
        _condenserModule = new MockCondenserModule(address(_auctionHouse));
        _condenserModuleKeycode = keycodeFromVeecode(_condenserModule.VEECODE());

        _allowlist = new MockAllowlist();
        _hook = new MockHook(address(_quoteToken), address(_baseToken));

        _startTime = uint48(block.timestamp) + 1;

        _auctionParams = Auction.AuctionParams({
            start: _startTime,
            duration: _duration,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode("")
        });

        _routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode(""),
            baseToken: _baseToken,
            quoteToken: _quoteToken,
            curator: _CURATOR,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: _derivativeParams
        });

        // Bidder
        _bidderKey = _getRandomUint256();
        _bidder = vm.addr(_bidderKey);
    }

    // ===== Helper Functions ===== //

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

    // ===== Modifiers ===== //

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", decimals_);

        uint96 lotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        // Update routing params
        _routingParams.baseToken = _baseToken;

        // Update auction params
        _auctionParams.capacity = uint96(lotCapacity);

        // Update the hook
        _hook.setPayoutToken(address(_baseToken));
    }

    modifier givenBaseTokenHasDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", decimals_);

        // Update routing params
        _routingParams.quoteToken = _quoteToken;

        // Update the hook
        _hook.setQuoteToken(address(_quoteToken));
    }

    modifier givenQuoteTokenHasDecimals(uint8 decimals_) {
        _setQuoteTokenDecimals(decimals_);
        _;
    }

    modifier whenAuctionTypeIsAtomic() {
        _routingParams.auctionType = _atomicAuctionModuleKeycode;

        _auctionModule = _atomicAuctionModule;
        _auctionModuleKeycode = _atomicAuctionModuleKeycode;
        _;
    }

    modifier whenAuctionTypeIsBatch() {
        _routingParams.auctionType = _batchAuctionModuleKeycode;

        _auctionModule = _batchAuctionModule;
        _auctionModuleKeycode = _batchAuctionModuleKeycode;
        _;
    }

    modifier whenAtomicAuctionModuleIsInstalled() {
        _auctionHouse.installModule(_atomicAuctionModule);
        _;
    }

    modifier whenBatchAuctionModuleIsInstalled() {
        _auctionHouse.installModule(_batchAuctionModule);
        _;
    }

    modifier whenDerivativeTypeIsSet() {
        _routingParams.derivativeType = _derivativeModuleKeycode;
        _;
    }

    modifier whenDerivativeModuleIsInstalled() {
        _auctionHouse.installModule(_derivativeModule);
        _;
    }

    modifier givenLotIsCreated() {
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
        _;
    }

    modifier givenLotHasStarted() {
        vm.warp(_startTime);
        _;
    }

    modifier givenLotIsCancelled() {
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId);
        _;
    }

    modifier givenLotIsConcluded() {
        vm.warp(_startTime + _duration + 1);
        _;
    }

    modifier givenLotHasAllowlist() {
        _routingParams.allowlist = _allowlist;
        _;
    }

    modifier whenAllowlistProofIsCorrect() {
        // Add the sender to the allowlist
        _allowlist.setAllowedWithProof(_bidder, _allowlistProof, true);
        _;
    }

    modifier whenAllowlistProofIsIncorrect() {
        _allowlistProof = abi.encode("incorrect proof");
        _;
    }

    modifier whenPermit2ApprovalIsProvided(uint256 amount_) {
        // Approve the Permit2 contract to spend the quote token
        vm.prank(_bidder);
        _quoteToken.approve(_PERMIT2_ADDRESS, type(uint256).max);

        // Set up the Permit2 approval
        uint48 deadline = uint48(block.timestamp);
        uint256 nonce = _getRandomUint256();
        bytes memory signature = _signPermit(
            address(_quoteToken), amount_, nonce, deadline, address(_auctionHouse), _bidderKey
        );

        _permit2Data = abi.encode(
            Transfer.Permit2Approval({deadline: deadline, nonce: nonce, signature: signature})
        );
        _;
    }

    modifier givenUserHasQuoteTokenBalance(uint256 amount_) {
        _quoteToken.mint(_bidder, amount_);
        _;
    }

    modifier givenUserHasQuoteTokenAllowance(uint256 amount_) {
        vm.prank(_bidder);
        _quoteToken.approve(address(_auctionHouse), amount_);
        _;
    }

    modifier givenSellerHasBaseTokenBalance(uint256 amount_) {
        _baseToken.mint(_SELLER, amount_);
        _;
    }

    modifier givenSellerHasBaseTokenAllowance(uint256 amount_) {
        vm.prank(_SELLER);
        _baseToken.approve(address(_auctionHouse), amount_);
        _;
    }

    modifier givenAuctionHasHook() {
        _routingParams.hooks = _hook;
        _;
    }

    modifier givenHookHasBaseTokenBalance(uint256 amount_) {
        _baseToken.mint(address(_hook), amount_);
        _;
    }

    modifier givenHookHasBaseTokenAllowance(uint256 amount_) {
        vm.prank(address(_hook));
        _baseToken.approve(address(_auctionHouse), amount_);
        _;
    }

    function _createBid(uint96 amount_, bytes memory auctionData_) internal returns (uint64) {
        Router.BidParams memory bidParams = Router.BidParams({
            lotId: _lotId,
            referrer: _REFERRER,
            amount: amount_,
            auctionData: auctionData_,
            allowlistProof: _allowlistProof,
            permit2Data: _permit2Data
        });

        vm.prank(_bidder);
        _bidId = _auctionHouse.bid(bidParams);

        return _bidId;
    }

    modifier givenBid(uint96 amount_, bytes memory auctionData_) {
        _createBid(amount_, auctionData_);
        _;
    }

    function _createPurchase(
        uint96 amount_,
        uint96 minAmountOut_,
        bytes memory auctionData_,
        address referrer_
    ) internal returns (uint256) {
        Router.PurchaseParams memory purchaseParams = Router.PurchaseParams({
            recipient: _bidder,
            referrer: referrer_,
            lotId: _lotId,
            amount: amount_,
            minAmountOut: minAmountOut_,
            auctionData: auctionData_,
            allowlistProof: _allowlistProof,
            permit2Data: _permit2Data
        });

        vm.prank(_bidder);
        uint256 payout = _auctionHouse.purchase(purchaseParams);

        return payout;
    }

    function _createPurchase(
        uint96 amount_,
        uint96 minAmountOut_,
        bytes memory auctionData_
    ) internal returns (uint256) {
        return _createPurchase(amount_, minAmountOut_, auctionData_, _REFERRER);
    }

    modifier givenPurchase(uint96 amount_, uint96 minAmountOut_, bytes memory auctionData_) {
        // Purchase
        _createPurchase(amount_, minAmountOut_, auctionData_);
        _;
    }

    modifier givenCuratorIsSet() {
        _routingParams.curator = _CURATOR;
        _;
    }

    modifier givenCuratorMaxFeeIsSet() {
        _auctionHouse.setFee(
            _auctionModuleKeycode, FeeManager.FeeType.MaxCurator, _CURATOR_MAX_FEE_PERCENT
        );
        _;
    }

    modifier givenCuratorFeeIsSet() {
        // Set the curator fee
        vm.prank(_CURATOR);
        _auctionHouse.setCuratorFee(_auctionModuleKeycode, _CURATOR_FEE_PERCENT);
        _curatorFeePercentActual = _CURATOR_FEE_PERCENT;
        _curatorMaxPotentialFee = _curatorFeePercentActual * _LOT_CAPACITY / 1e5;
        _;
    }

    modifier givenCuratorHasApproved() {
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId);
        _curatorApproved = true;
        _;
    }

    modifier givenProtocolFeeIsSet() {
        _auctionHouse.setFee(
            _auctionModuleKeycode, FeeManager.FeeType.Protocol, _PROTOCOL_FEE_PERCENT
        );
        _protocolFeePercentActual = _PROTOCOL_FEE_PERCENT;
        _;
    }

    modifier givenReferrerFeeIsSet() {
        _auctionHouse.setFee(
            _auctionModuleKeycode, FeeManager.FeeType.Referrer, _REFERRER_FEE_PERCENT
        );
        _referrerFeePercentActual = _REFERRER_FEE_PERCENT;
        _;
    }

    modifier givenAtomicAuctionRequiresPrefunding() {
        _atomicAuctionModule.setRequiredPrefunding(true);
        _;
    }

    // ===== Helpers ===== //

    function _getLotRouting(uint96 lotId_) internal view returns (Auctioneer.Routing memory) {
        (
            Veecode auctionReference_,
            address seller_,
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
            seller: seller_,
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
        (address curator_, bool curated_, uint48 curatorFee_) = _auctionHouse.lotCuration(lotId_);

        return Auctioneer.Curation({curator: curator_, curated: curated_, curatorFee: curatorFee_});
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
}
