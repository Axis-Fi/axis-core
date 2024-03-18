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
import {MockCallback} from "test/AuctionHouse/MockCallback.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";

// Auctions
import {AuctionHouse, Router} from "src/AuctionHouse.sol";
import {Auction, AuctionModule} from "src/modules/Auction.sol";
import {FeeManager} from "src/bases/FeeManager.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";
import {Catalogue} from "src/Catalogue.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

import {Veecode, toKeycode, keycodeFromVeecode, Keycode} from "src/modules/Modules.sol";

import {console2} from "forge-std/console2.sol";

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
    MockCallback internal _callback;

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

        _auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _catalogue = new Catalogue(address(_auctionHouse));

        _atomicAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));
        _atomicAuctionModuleKeycode = keycodeFromVeecode(_atomicAuctionModule.VEECODE());
        _batchAuctionModule = new MockBatchAuctionModule(address(_auctionHouse));
        _batchAuctionModuleKeycode = keycodeFromVeecode(_batchAuctionModule.VEECODE());
        _derivativeModule = new MockDerivativeModule(address(_auctionHouse));
        _derivativeModuleKeycode = keycodeFromVeecode(_derivativeModule.VEECODE());

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
            callbacks: ICallback(address(0)),
            callbackData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: _derivativeParams,
            wrapDerivative: false,
            prefunded: false
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

    modifier whenAuctionTypeIsAtomic() {
        _routingParams.auctionType = _atomicAuctionModuleKeycode;

        _auctionModule = _atomicAuctionModule;
        _auctionModuleKeycode = _atomicAuctionModuleKeycode;
        _;
    }

    modifier whenAuctionTypeIsBatch() {
        _routingParams.auctionType = _batchAuctionModuleKeycode;
        _routingParams.prefunded = true;

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

    function _settleLot() internal {
        vm.prank(_SELLER);
        _auctionHouse.settle(_lotId);
    }

    modifier givenLotIsSettled() {
        _settleLot();
        _;
    }

    modifier givenLotHasAllowlist() {
        // Allowlist callback supports onCreate, onPurchase, and onBid callbacks
        // // 10011000 = 0x98
        // // cast create2 -s 98 -i $(cat ./bytecode/MockCallback98.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(address(_auctionHouse), Callbacks.Permissions({
        //         onCreate: true,
        //         onCancel: false,
        //         onCurate: false,
        //         onPurchase: true,
        //         onBid: true,
        //         onClaimProceeds: false,
        //         receiveQuoteTokens: false,
        //         sendBaseTokens: false
        //     }), _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallback98.bin",
        //     vm.toString(bytecode)
        // );

        bytes32 salt = bytes32(0xab1ab3789d4493b63a77e1fb31f5cfa877ae54d27913efbabfa9247be92c0a83);
        vm.broadcast(); // required for CREATE2 address to work correctly. doesn't do anything in a test
        _callback = new MockCallback{salt: salt}(
            address(_auctionHouse),
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: true,
                onClaimProceeds: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            _SELLER
        );

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
        // Uncomment to regenerate bytecode to mine new salts if the MockCallback changes
        // // 11111111 = 0xFF
        // // cast create2 -s FF -i $(cat ./bytecode/MockCallbackFF.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(address(_auctionHouse), Callbacks.Permissions({
        //         onCreate: true,
        //         onCancel: true,
        //         onCurate: true,
        //         onPurchase: true,
        //         onBid: true,
        //         onClaimProceeds: true,
        //         receiveQuoteTokens: true,
        //         sendBaseTokens: true
        //     }), _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallbackFF.bin",
        //     vm.toString(bytecode)
        // );
        // // 11111101 = 0xFD
        // // cast create2 -s FD -i $(cat ./bytecode/MockCallbackFD.bin)
        // bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(address(_auctionHouse), Callbacks.Permissions({
        //         onCreate: true,
        //         onCancel: true,
        //         onCurate: true,
        //         onPurchase: true,
        //         onBid: true,
        //         onClaimProceeds: true,
        //         receiveQuoteTokens: false,
        //         sendBaseTokens: true
        //     }), _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallbackFD.bin",
        //     vm.toString(bytecode)
        // );
        // // 11111110 = 0xFE
        // // cast create2 -s FE -i $(cat ./bytecode/MockCallbackFE.bin)
        // bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(address(_auctionHouse), Callbacks.Permissions({
        //         onCreate: true,
        //         onCancel: true,
        //         onCurate: true,
        //         onPurchase: true,
        //         onBid: true,
        //         onClaimProceeds: true,
        //         receiveQuoteTokens: true,
        //         sendBaseTokens: false
        //     }), _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallbackFE.bin",
        //     vm.toString(bytecode)
        // );
        // // 11111100 = 0xFC
        // // cast create2 -s FC -i $(cat ./bytecode/MockCallbackFC.bin)
        // bytecode = abi.encodePacked(
        //     type(MockCallback).creationCode,
        //     abi.encode(address(_auctionHouse), Callbacks.Permissions({
        //         onCreate: true,
        //         onCancel: true,
        //         onCurate: true,
        //         onPurchase: true,
        //         onBid: true,
        //         onClaimProceeds: true,
        //         receiveQuoteTokens: false,
        //         sendBaseTokens: false
        //     }), _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/MockCallbackFC.bin",
        //     vm.toString(bytecode)
        // );

        // Set the salt based on which token flags are set
        bytes32 salt;
        if (_callbackSendBaseTokens && _callbackReceiveQuoteTokens) {
            // 11111111 = 0xFF
            salt = bytes32(0x32e1078b9d54a01af43eefd3a1917e0681b6ded11dd3fde80b19740b286706d9);
        } else if (_callbackSendBaseTokens) {
            // 11111101 = 0xFD
            salt = bytes32(0xfbc90e27b044a58cc9a38b7f1c61bafdfea6cd7972117afcb59af65e887d1a98);
        } else if (_callbackReceiveQuoteTokens) {
            // 11111110 = 0xFE
            salt = bytes32(0xb7f86ae56377b2fbd4cd9684e04cccedb89a2d8dd6a497695501b7b1bb2cfb17);
        } else {
            // 11111100 = 0xFC
            salt = bytes32(0x667ba1181a4f5ab0c74a749f9628c6c2d5939ba3fbdbb81a8d62f1f44babce6a);
        }

        vm.broadcast(); // required for CREATE2 address to work correctly. doesn't do anything in a test
        _callback = new MockCallback{salt: salt}(
            address(_auctionHouse),
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: true,
                onBid: true,
                onClaimProceeds: true,
                receiveQuoteTokens: _callbackReceiveQuoteTokens,
                sendBaseTokens: _callbackSendBaseTokens
            }),
            _SELLER
        );
        console2.log("callback", address(_callback));

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

    function _createBid(
        address bidder_,
        uint96 amount_,
        bytes memory auctionData_
    ) internal returns (uint64) {
        Router.BidParams memory bidParams = Router.BidParams({
            lotId: _lotId,
            referrer: _REFERRER,
            amount: amount_,
            auctionData: auctionData_,
            permit2Data: _permit2Data
        });

        vm.prank(bidder_);
        _bidId = _auctionHouse.bid(bidParams, _allowlistProof);

        return _bidId;
    }

    function _createBid(uint96 amount_, bytes memory auctionData_) internal returns (uint64) {
        return _createBid(_bidder, amount_, auctionData_);
    }

    modifier givenBid(uint96 amount_, bytes memory auctionData_) {
        uint64 bidId = _createBid(amount_, auctionData_);

        _bidIds.push(bidId);
        _;
    }

    modifier givenBidCreated(address bidder_, uint96 amount_, bytes memory auctionData_) {
        uint64 bidId = _createBid(bidder_, amount_, auctionData_);

        _bidIds.push(bidId);
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
            permit2Data: _permit2Data
        });

        vm.prank(_bidder);
        uint256 payout = _auctionHouse.purchase(purchaseParams, _allowlistProof);

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
        _auctionHouse.setFee(_auctionModuleKeycode, FeeManager.FeeType.Protocol, fee_);
        _protocolFeePercentActual = fee_;
    }

    modifier givenProtocolFeeIsSet() {
        _setProtocolFee(_PROTOCOL_FEE_PERCENT);
        _;
    }

    function _setReferrerFee(uint24 fee_) internal {
        _auctionHouse.setFee(_auctionModuleKeycode, FeeManager.FeeType.Referrer, fee_);
        _referrerFeePercentActual = fee_;
    }

    modifier givenReferrerFeeIsSet() {
        _setReferrerFee(_REFERRER_FEE_PERCENT);
        _;
    }

    modifier givenAuctionIsPrefunded() {
        _routingParams.prefunded = true;
        _;
    }

    modifier givenLotProceedsAreClaimed() {
        vm.prank(_SELLER);
        _auctionHouse.claimProceeds(_lotId, bytes(""));
        _;
    }

    modifier givenBidIsClaimed(uint64 bidId_) {
        uint64[] memory bids = new uint64[](1);
        bids[0] = bidId_;

        vm.prank(_bidder);
        _auctionHouse.claimBids(_lotId, bids);
        _;
    }

    // ===== Helpers ===== //

    function _getLotRouting(uint96 lotId_) internal view returns (Auctioneer.Routing memory) {
        (
            address seller_,
            uint96 prefunding_,
            ERC20 baseToken_,
            Veecode auctionReference_,
            ERC20 quoteToken_,
            ICallback callback_,
            Veecode derivativeReference_,
            bool wrapDerivative_,
            bytes memory derivativeParams_
        ) = _auctionHouse.lotRouting(lotId_);

        return Auctioneer.Routing({
            auctionReference: auctionReference_,
            seller: seller_,
            baseToken: baseToken_,
            quoteToken: quoteToken_,
            callbacks: callback_,
            derivativeReference: derivativeReference_,
            derivativeParams: derivativeParams_,
            wrapDerivative: wrapDerivative_,
            funding: prefunding_
        });
    }

    function _getLotFees(uint96 lotId_) internal view returns (Auctioneer.FeeData memory) {
        (
            address curator_,
            bool curated_,
            uint48 curatorFee_,
            uint48 protocolFee_,
            uint48 referrerFee_
        ) = _auctionHouse.lotFees(lotId_);

        return Auctioneer.FeeData({
            curator: curator_,
            curated: curated_,
            curatorFee: curatorFee_,
            protocolFee: protocolFee_,
            referrerFee: referrerFee_
        });
    }

    function _getLotData(uint96 lotId_) internal view returns (Auction.Lot memory) {
        return _auctionModule.getLot(lotId_);
    }
}
