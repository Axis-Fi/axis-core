// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Interfaces
import {IAuction} from "src/interfaces/IAuction.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {IAtomicAuctionHouse} from "src/interfaces/IAtomicAuctionHouse.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {IFeeManager} from "src/interfaces/IFeeManager.sol";

// Internal libraries
import {Callbacks} from "src/lib/Callbacks.sol";
import {Transfer} from "src/lib/Transfer.sol";

// External libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// Mocks
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockDerivativeModule} from "test/modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockCondenserModule} from "test/modules/Condenser/MockCondenserModule.sol";
import {MockCallback} from "test/callbacks/MockCallback.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";

// Auctions
import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {AuctionModule} from "src/modules/Auction.sol";

import {Veecode, toKeycode, keycodeFromVeecode, Keycode} from "src/modules/Keycode.sol";

import {WithSalts} from "test/lib/WithSalts.sol";

abstract contract AtomicAuctionHouseTest is Test, Permit2User, WithSalts {
    MockFeeOnTransferERC20 internal _baseToken;
    MockFeeOnTransferERC20 internal _quoteToken;

    AtomicAuctionHouse internal _auctionHouse;
    AuctionModule internal _auctionModule;
    Keycode internal _auctionModuleKeycode;
    // Catalogue internal _catalogue;

    MockAtomicAuctionModule internal _atomicAuctionModule;
    Keycode internal _atomicAuctionModuleKeycode;
    MockDerivativeModule internal _derivativeModule;
    Keycode internal _derivativeModuleKeycode;
    MockCondenserModule internal _condenserModule;
    Keycode internal _condenserModuleKeycode;
    MockCallback internal _callback;

    uint256 internal constant _BASE_SCALE = 1e18;

    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _CURATOR = address(0x4);
    address internal constant _RECIPIENT = address(0x5);
    address internal constant _REFERRER = address(0x6);

    address internal _bidder;
    uint256 internal _bidderKey;

    uint24 internal constant _CURATOR_MAX_FEE_PERCENT = 100;
    uint24 internal constant _CURATOR_FEE_PERCENT = 90;
    uint24 internal _curatorFeePercentActual;

    uint24 internal constant _PROTOCOL_FEE_PERCENT = 100;
    uint24 internal constant _REFERRER_FEE_PERCENT = 105;
    uint24 internal _protocolFeePercentActual;
    uint24 internal _referrerFeePercentActual;

    uint256 internal _curatorMaxPotentialFee;
    bool internal _curatorApproved;

    // Input to parameters
    uint48 internal _startTime;
    uint48 internal _duration = 1 days;
    /// @dev    Needs to be updated if the base token scale is changed
    uint256 internal constant _LOT_CAPACITY = 10e18;
    string internal constant _INFO_HASH = "info hash";
    bytes internal _derivativeParams = abi.encode("");

    // Parameters
    IAuctionHouse.RoutingParams internal _routingParams;
    IAuction.AuctionParams internal _auctionParams;
    bytes internal _allowlistProof;
    bytes internal _permit2Data;
    bool internal _callbackSendBaseTokens;
    bool internal _callbackReceiveQuoteTokens;

    // Outputs
    uint96 internal _lotId = type(uint96).max; // Set to max to ensure it's not a valid lot id
    uint64 internal _bidId = type(uint64).max; // Set to max to ensure it's not a valid bid id
    uint64[] internal _bidIds;

    function setUp() public {
        // Set block timestamp
        vm.warp(1_000_000);

        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", 18);
        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);

        // Create an AtomicAuctionHouse at a deterministic address, since it is used as input to callbacks
        AtomicAuctionHouse auctionHouse = new AtomicAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = AtomicAuctionHouse(address(0x000000000000000000000000000000000000000A));
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(7)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        _atomicAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));
        _atomicAuctionModuleKeycode = keycodeFromVeecode(_atomicAuctionModule.VEECODE());
        _derivativeModule = new MockDerivativeModule(address(_auctionHouse));
        _derivativeModuleKeycode = keycodeFromVeecode(_derivativeModule.VEECODE());
        _condenserModule = new MockCondenserModule(address(_auctionHouse));
        _condenserModuleKeycode = keycodeFromVeecode(_condenserModule.VEECODE());

        _startTime = uint48(block.timestamp) + 1;

        _auctionParams = IAuction.AuctionParams({
            start: _startTime,
            duration: _duration,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode("")
        });

        _routingParams = IAuctionHouse.RoutingParams({
            auctionType: toKeycode(""),
            baseToken: address(_baseToken),
            quoteToken: address(_quoteToken),
            curator: _CURATOR,
            callbacks: ICallback(address(0)),
            callbackData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: _derivativeParams,
            wrapDerivative: false
        });

        // Bidder
        _bidderKey = _getRandomUint256();
        _bidder = vm.addr(_bidderKey);
    }

    // ===== Helper Functions ===== //

    function _scaleQuoteTokenAmount(uint256 amount_) internal view returns (uint256) {
        return FixedPointMathLib.mulDivDown(amount_, 10 ** _quoteToken.decimals(), _BASE_SCALE);
    }

    function _scaleBaseTokenAmount(uint256 amount_) internal view returns (uint256) {
        return FixedPointMathLib.mulDivDown(amount_, 10 ** _baseToken.decimals(), _BASE_SCALE);
    }

    // ===== Modifiers ===== //

    function _setBaseTokenDecimals(uint8 decimals_) internal {
        _baseToken = new MockFeeOnTransferERC20("Base Token", "BASE", decimals_);

        uint256 lotCapacity = _scaleBaseTokenAmount(_LOT_CAPACITY);

        // Update routing params
        _routingParams.baseToken = address(_baseToken);

        // Update auction params
        _auctionParams.capacity = lotCapacity;
    }

    modifier givenBaseTokenHasDecimals(uint8 decimals_) {
        _setBaseTokenDecimals(decimals_);
        _;
    }

    function _setQuoteTokenDecimals(uint8 decimals_) internal {
        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", decimals_);

        // Update routing params
        _routingParams.quoteToken = address(_quoteToken);
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

    modifier whenAtomicAuctionModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_atomicAuctionModule);
        _;
    }

    modifier whenDerivativeTypeIsSet() {
        _routingParams.derivativeType = _derivativeModuleKeycode;
        _;
    }

    modifier whenDerivativeModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_derivativeModule);
        _;
    }

    modifier whenCondenserModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_condenserModule);
        _;
    }

    modifier whenCondenserIsMapped() {
        vm.startPrank(_OWNER);
        _auctionHouse.setCondenser(
            _atomicAuctionModule.VEECODE(), _derivativeModule.VEECODE(), _condenserModule.VEECODE()
        );
        vm.stopPrank();
        _;
    }

    modifier givenLotIsCreated() {
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _INFO_HASH);
        _;
    }

    function _startLot() internal {
        vm.warp(_startTime);
    }

    modifier givenLotHasStarted() {
        _startLot();
        _;
    }

    modifier givenLotIsCancelled() {
        vm.prank(_SELLER);
        _auctionHouse.cancel(_lotId, bytes(""));
        _;
    }

    function _concludeLot() internal {
        vm.warp(_startTime + _duration + 1);
    }

    modifier givenLotIsConcluded() {
        _concludeLot();
        _;
    }

    modifier givenLotHasAllowlist() {
        // Get the salt
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });
        bytes memory args = abi.encode(address(_auctionHouse), permissions);
        bytes32 salt = _getSalt("MockCallback", type(MockCallback).creationCode, args);

        vm.startBroadcast(); // required for CREATE2 address to work correctly. doesn't do anything in a test
        _callback = new MockCallback{salt: salt}(address(_auctionHouse), permissions);
        vm.stopBroadcast();

        _routingParams.callbacks = _callback;

        // Set allowlist enabled on the callback
        _callback.setAllowlistEnabled(true);
        _;
    }

    modifier whenAllowlistProofIsCorrect() {
        // Add the sender to the allowlist
        _callback.setAllowedWithProof(_bidder, _allowlistProof, true);
        _;
    }

    modifier whenAllowlistProofIsIncorrect() {
        _allowlistProof = abi.encode("incorrect proof");
        _;
    }

    modifier whenPermit2ApprovalIsProvided(uint256 amount_) {
        // Approve the Permit2 contract to spend the quote token
        vm.prank(_bidder);
        _quoteToken.approve(_permit2Address, type(uint256).max);

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

    modifier givenCallbackIsSet() {
        // Get the salt
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: true,
            onCurate: true,
            onPurchase: true,
            onBid: true,
            onClaimProceeds: true,
            receiveQuoteTokens: _callbackReceiveQuoteTokens,
            sendBaseTokens: _callbackSendBaseTokens
        });
        bytes memory args = abi.encode(address(_auctionHouse), permissions);
        bytes32 salt = _getSalt("MockCallback", type(MockCallback).creationCode, args);

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast(); // required for CREATE2 address to work correctly. doesn't do anything in a test
        _callback = new MockCallback{salt: salt}(address(_auctionHouse), permissions);
        vm.stopBroadcast();

        _routingParams.callbacks = _callback;
        _;
    }

    modifier givenCallbackHasSendBaseTokensFlag() {
        _callbackSendBaseTokens = true;
        _;
    }

    modifier givenCallbackHasReceiveQuoteTokensFlag() {
        _callbackReceiveQuoteTokens = true;
        _;
    }

    modifier givenCallbackHasBaseTokenBalance(uint256 amount_) {
        _baseToken.mint(address(_callback), amount_);
        _;
    }

    modifier givenCallbackHasBaseTokenAllowance(uint256 amount_) {
        vm.prank(address(_callback));
        _baseToken.approve(address(_auctionHouse), amount_);
        _;
    }

    function _createPurchase(
        uint256 amount_,
        uint256 minAmountOut_,
        bytes memory auctionData_,
        address referrer_
    ) internal returns (uint256) {
        IAtomicAuctionHouse.PurchaseParams memory purchaseParams = IAtomicAuctionHouse
            .PurchaseParams({
            recipient: _bidder,
            referrer: referrer_,
            lotId: _lotId,
            amount: amount_,
            minAmountOut: minAmountOut_,
            auctionData: auctionData_,
            permit2Data: _permit2Data
        });

        vm.prank(_bidder);
        uint256 payout = _auctionHouse.purchase(purchaseParams, _allowlistProof);

        return payout;
    }

    function _createPurchase(
        uint256 amount_,
        uint256 minAmountOut_,
        bytes memory auctionData_
    ) internal returns (uint256) {
        return _createPurchase(amount_, minAmountOut_, auctionData_, _REFERRER);
    }

    modifier givenPurchase(uint256 amount_, uint256 minAmountOut_, bytes memory auctionData_) {
        // Purchase
        _createPurchase(amount_, minAmountOut_, auctionData_);
        _;
    }

    modifier givenCuratorIsSet() {
        _routingParams.curator = _CURATOR;
        _;
    }

    modifier givenCuratorMaxFeeIsSet() {
        vm.prank(_OWNER);
        _auctionHouse.setFee(
            _auctionModuleKeycode, IFeeManager.FeeType.MaxCurator, _CURATOR_MAX_FEE_PERCENT
        );
        _;
    }

    function _setCuratorFee(uint24 fee_) internal {
        vm.prank(_CURATOR);
        _auctionHouse.setCuratorFee(_auctionModuleKeycode, fee_);
        _curatorFeePercentActual = fee_;
        _curatorMaxPotentialFee = _curatorFeePercentActual * _LOT_CAPACITY / 1e5;
    }

    modifier givenCuratorFeeIsSet() {
        _setCuratorFee(_CURATOR_FEE_PERCENT);
        _;
    }

    modifier givenCuratorHasApproved() {
        vm.prank(_CURATOR);
        _auctionHouse.curate(_lotId, bytes(""));
        _curatorApproved = true;
        _;
    }

    function _setProtocolFee(uint24 fee_) internal {
        vm.prank(_OWNER);
        _auctionHouse.setFee(_auctionModuleKeycode, IFeeManager.FeeType.Protocol, fee_);
        _protocolFeePercentActual = fee_;
    }

    modifier givenProtocolFeeIsSet() {
        _setProtocolFee(_PROTOCOL_FEE_PERCENT);
        _;
    }

    function _setReferrerFee(uint24 fee_) internal {
        vm.prank(_OWNER);
        _auctionHouse.setFee(_auctionModuleKeycode, IFeeManager.FeeType.Referrer, fee_);
        _referrerFeePercentActual = fee_;
    }

    modifier givenReferrerFeeIsSet() {
        _setReferrerFee(_REFERRER_FEE_PERCENT);
        _;
    }

    // ===== Helpers ===== //

    function _getLotRouting(uint96 lotId_) internal view returns (AuctionHouse.Routing memory) {
        (
            address seller_,
            ERC20 baseToken_,
            ERC20 quoteToken_,
            Veecode auctionReference_,
            uint256 funding_,
            ICallback callback_,
            Veecode derivativeReference_,
            bool wrapDerivative_,
            bytes memory derivativeParams_
        ) = _auctionHouse.lotRouting(lotId_);

        return AuctionHouse.Routing({
            auctionReference: auctionReference_,
            seller: seller_,
            baseToken: baseToken_,
            quoteToken: quoteToken_,
            callbacks: callback_,
            derivativeReference: derivativeReference_,
            derivativeParams: derivativeParams_,
            wrapDerivative: wrapDerivative_,
            funding: funding_
        });
    }

    function _getLotFees(uint96 lotId_) internal view returns (AuctionHouse.FeeData memory) {
        (
            address curator_,
            bool curated_,
            uint48 curatorFee_,
            uint48 protocolFee_,
            uint48 referrerFee_
        ) = _auctionHouse.lotFees(lotId_);

        return AuctionHouse.FeeData({
            curator: curator_,
            curated: curated_,
            curatorFee: curatorFee_,
            protocolFee: protocolFee_,
            referrerFee: referrerFee_
        });
    }

    function _getLotData(uint96 lotId_) internal view returns (IAuction.Lot memory) {
        return _auctionModule.getLot(lotId_);
    }
}
