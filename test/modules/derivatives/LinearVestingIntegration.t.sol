// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {StringHelper} from "test/lib/String.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IHooks, IAllowlist, Auctioneer} from "src/bases/Auctioneer.sol";
import {AuctionHouse, Router} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {Catalogue} from "src/Catalogue.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {LocalSealedBidBatchAuction} from "src/modules/auctions/LSBBA/LSBBA.sol";
import {RSAOAEP} from "src/lib/RSA.sol";
import {uint2str} from "src/lib/Uint2Str.sol";

import {toKeycode, unwrapVeecode, Keycode, fromKeycode} from "src/modules/Modules.sol";

contract LinearVestingIntegrationTest is Test, Permit2User {
    using StringHelper for string;
    using FixedPointMathLib for uint256;

    address internal constant _owner = address(0x1);
    address internal constant _protocol = address(0x2);
    address internal constant _alice = address(0x3);
    address internal constant _recipient = address(0x4);
    address internal constant _referrer = address(0x5);

    MockERC20 internal quoteToken;
    MockERC20 internal underlyingToken;
    address internal underlyingTokenAddress;
    uint8 internal underlyingTokenDecimals = 18;

    AuctionHouse internal auctionHouse;
    Catalogue internal catalogue;
    LinearVesting internal linearVesting;
    MockAtomicAuctionModule internal mockAtomicAuctionModule;
    LocalSealedBidBatchAuction internal localSealedBidBatchAuctionModule;

    uint256 internal constant LOT_CAPACITY = 10e18;
    uint256 internal constant BID_AMOUNT = 1e18;
    uint256 internal constant BID_AMOUNT_OUT = 1e18;
    bytes32 internal constant BID_SEED = bytes32(uint256(1e9));

    uint96 internal lotId;
    uint96 internal bidId;

    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    LocalSealedBidBatchAuction.AuctionDataParams internal batchAuctionDataParams;
    bytes internal constant PUBLIC_KEY_MODULUS = abi.encodePacked(
        bytes32(0xB925394F570C7C765F121826DFC8A1661921923B33408EFF62DCAC0D263952FE),
        bytes32(0x158C12B2B35525F7568CB8DC7731FBC3739F22D94CB80C5622E788DB4532BD8C),
        bytes32(0x8643680DA8C00A5E7C967D9D087AA1380AE9A031AC292C971EC75F9BD3296AE1),
        bytes32(0x1AFCC05BD15602738CBE9BD75B76403AB2C9409F2CC0C189B4551DEE8B576AD3)
    );

    LinearVesting.VestingParams internal vestingParams;
    bytes internal vestingParamsBytes;
    uint48 internal constant vestingStart = 1_704_882_344; // 2024-01-10
    uint48 internal constant vestingExpiry = 1_705_055_144; // 2024-01-12
    uint48 internal constant vestingDuration = 2 days;

    // uint256 internal derivativeTokenId;
    // address internal derivativeWrappedAddress;
    // string internal wrappedDerivativeTokenName;
    // string internal wrappedDerivativeTokenSymbol;
    // uint256 internal wrappedDerivativeTokenNameLength;
    // uint256 internal wrappedDerivativeTokenSymbolLength;

    function setUp() public {
        // Wrap to reasonable timestamp
        vm.warp(1_704_882_344);

        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        underlyingToken = new MockERC20("Underlying", "UNDERLYING", underlyingTokenDecimals);
        underlyingTokenAddress = address(underlyingToken);

        auctionHouse = new AuctionHouse(address(this), _protocol, _PERMIT2_ADDRESS);

        catalogue = new Catalogue(address(auctionHouse));

        // Mock atomic auction module
        mockAtomicAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));
        auctionHouse.installModule(mockAtomicAuctionModule);

        // Local sealed bid batch auction module
        localSealedBidBatchAuctionModule = new LocalSealedBidBatchAuction(address(auctionHouse));
        auctionHouse.installModule(localSealedBidBatchAuctionModule);

        // Derivative module
        linearVesting = new LinearVesting(address(auctionHouse));
        auctionHouse.installModule(linearVesting);

        // Derivative parameters
        vestingParams = LinearVesting.VestingParams({expiry: vestingExpiry});
        vestingParamsBytes = abi.encode(vestingParams);

        // wrappedDerivativeTokenName = "Underlying 2024-01-12";
        // wrappedDerivativeTokenSymbol = "UNDERLYING 2024-01-12";
        // wrappedDerivativeTokenNameLength = bytes(wrappedDerivativeTokenName).length;
        // wrappedDerivativeTokenSymbolLength = bytes(wrappedDerivativeTokenSymbol).length;

        // Auction parameters
        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("ATOM"),
            baseToken: underlyingToken,
            quoteToken: quoteToken,
            curator: address(0),
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode("LIV"),
            derivativeParams: abi.encode(vestingParams)
        });
    }

    // ===== Modifiers ===== //

    modifier givenAuctionIsAtomic() {
        // Set up auction parameters
        routingParams.auctionType = toKeycode("ATOM");

        // Create auction
        vm.prank(_owner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    modifier givenAuctionIsBatch() {
        batchAuctionDataParams = LocalSealedBidBatchAuction.AuctionDataParams({
            minFillPercent: 1000,
            minBidPercent: 1000,
            minimumPrice: 1e18,
            publicKeyModulus: PUBLIC_KEY_MODULUS
        });

        // Set up auction parameters
        routingParams.auctionType = toKeycode("LSBBA");
        auctionParams.implParams = abi.encode(batchAuctionDataParams);

        // Create auction
        vm.prank(_owner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    modifier givenOwnerHasBaseTokenBalance(uint256 amount_) {
        underlyingToken.mint(_owner, amount_);

        // Approve transfer
        vm.prank(_owner);
        underlyingToken.approve(address(auctionHouse), amount_);
        _;
    }

    modifier givenAuctionHasStarted() {
        vm.warp(uint48(block.timestamp) + 1);
        _;
    }

    modifier givenAuctionHasEnded() {
        vm.warp(uint48(block.timestamp) + auctionParams.duration + 1);
        _;
    }

    function _encrypt(LocalSealedBidBatchAuction.Decrypt memory decrypt_)
        internal
        view
        returns (bytes memory)
    {
        return RSAOAEP.encrypt(
            abi.encodePacked(decrypt_.amountOut),
            abi.encodePacked(uint2str(lotId)),
            abi.encodePacked(uint24(65_537)),
            PUBLIC_KEY_MODULUS,
            decrypt_.seed
        );
    }

    function _createBid(
        uint256 bidAmount_,
        uint256 bidAmountOut_
    ) internal view returns (Router.BidParams memory) {
        // Encrypt the bid amount
        LocalSealedBidBatchAuction.Decrypt memory decryptedBid =
            LocalSealedBidBatchAuction.Decrypt({amountOut: bidAmountOut_, seed: BID_SEED});
        bytes memory bidData = _encrypt(decryptedBid);

        return Router.BidParams({
            lotId: lotId,
            recipient: _recipient,
            referrer: _referrer,
            amount: bidAmount_,
            auctionData: bidData,
            allowlistProof: bytes(""),
            permit2Data: bytes("")
        });
    }

    modifier givenAuctionHasBid() {
        Router.BidParams memory bidParams = _createBid(BID_AMOUNT, BID_AMOUNT_OUT);

        // Approve transfer
        vm.prank(_alice);
        underlyingToken.approve(address(auctionHouse), BID_AMOUNT);

        // Bid
        vm.prank(_alice);
        bidId = auctionHouse.bid(bidParams);
        _;
    }

    modifier givenAuctionHasSettled() {
        // Decrypt
        LocalSealedBidBatchAuction.Decrypt memory decryptedBid =
            LocalSealedBidBatchAuction.Decrypt({amountOut: BID_AMOUNT_OUT, seed: BID_SEED});
        LocalSealedBidBatchAuction.Decrypt[] memory decryptedBids =
            new LocalSealedBidBatchAuction.Decrypt[](1);
        decryptedBids[0] = decryptedBid;

        // Decrypt and sort bids
        localSealedBidBatchAuctionModule.decryptAndSortBids(lotId, decryptedBids);

        // Settle
        auctionHouse.settle(lotId);
        _;
    }

    modifier givenUserHasQuoteTokenBalance(uint256 amount_) {
        quoteToken.mint(_alice, amount_);

        // Approve transfer
        vm.prank(_alice);
        quoteToken.approve(address(auctionHouse), amount_);
        _;
    }

    modifier givenAuctionHasPurchase() {
        Router.PurchaseParams memory purchaseParams = Router.PurchaseParams({
            recipient: _recipient,
            referrer: _referrer,
            lotId: lotId,
            amount: BID_AMOUNT,
            minAmountOut: BID_AMOUNT,
            auctionData: bytes(""),
            allowlistProof: bytes(""),
            permit2Data: bytes("")
        });

        // Approve transfer
        vm.prank(_alice);
        underlyingToken.approve(address(auctionHouse), BID_AMOUNT);

        // Purchase
        vm.prank(_alice);
        auctionHouse.purchase(purchaseParams);
        _;
    }

    // ===== Tests ===== //

    // auction
    // [X] it creates the auction with the correct parameters

    function test_auction_givenAtomic()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenAuctionIsAtomic
    {
        Auctioneer.Routing memory routingData = catalogue.getRouting(lotId);
        (Keycode auctionType,) = unwrapVeecode(routingData.auctionReference);
        assertEq(fromKeycode(auctionType), "ATOM", "auction type mismatch");

        (Keycode derivativeType,) = unwrapVeecode(routingData.derivativeReference);
        assertEq(fromKeycode(derivativeType), "LIV", "derivative type mismatch");
        assertEq(address(routingData.quoteToken), address(quoteToken), "quote token mismatch");
        assertEq(address(routingData.baseToken), underlyingTokenAddress, "base token mismatch");
        assertEq(routingData.derivativeParams, vestingParamsBytes, "derivative params mismatch");
        assertEq(routingData.prefunding, 0, "prefunding mismatch");

        // Base tokens have not been transferred
        assertEq(underlyingToken.balanceOf(address(auctionHouse)), 0, "base token balance mismatch");
        assertEq(underlyingToken.balanceOf(_owner), LOT_CAPACITY, "owner balance mismatch");
    }

    function test_auction_givenBatch()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenAuctionIsBatch
    {
        Auctioneer.Routing memory routingData = catalogue.getRouting(lotId);
        (Keycode auctionType,) = unwrapVeecode(routingData.auctionReference);
        assertEq(fromKeycode(auctionType), "LSBBA", "auction type mismatch");

        (Keycode derivativeType,) = unwrapVeecode(routingData.derivativeReference);
        assertEq(fromKeycode(derivativeType), "LIV", "derivative type mismatch");
        assertEq(address(routingData.quoteToken), address(quoteToken), "quote token mismatch");
        assertEq(address(routingData.baseToken), underlyingTokenAddress, "base token mismatch");
        assertEq(routingData.derivativeParams, vestingParamsBytes, "derivative params mismatch");
        assertEq(routingData.prefunding, LOT_CAPACITY, "prefunding mismatch"); // Due to LSBBA

        // Base tokens have been transferred
        assertEq(
            underlyingToken.balanceOf(address(auctionHouse)),
            LOT_CAPACITY,
            "base token balance mismatch"
        );
        assertEq(underlyingToken.balanceOf(_owner), 0, "owner balance mismatch");
    }

    // purchase
    // [X] given the auction is an atomic auction
    //  [X] derivative tokens are minted to the caller

    function test_purchase_givenAtomic()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenAuctionIsAtomic
        givenAuctionHasStarted
        givenUserHasQuoteTokenBalance(BID_AMOUNT)
        givenAuctionHasPurchase
    {
        // Get the derivative id
        uint256 derivativeTokenId =
            linearVesting.computeId(underlyingTokenAddress, routingParams.derivativeParams);

        // Derivative tokens have been minted to the recipient
        assertEq(
            linearVesting.balanceOf(_alice, derivativeTokenId),
            0,
            "derivative token: alice balance mismatch"
        );
        assertEq(
            linearVesting.balanceOf(_recipient, derivativeTokenId),
            BID_AMOUNT_OUT,
            "derivative token: recipient balance mismatch"
        );
        assertEq(
            linearVesting.balanceOf(_owner, derivativeTokenId),
            0,
            "derivative token: owner balance mismatch"
        );
        assertEq(
            linearVesting.balanceOf(address(auctionHouse), derivativeTokenId),
            0,
            "derivative token: auction house balance mismatch"
        );
        assertEq(
            linearVesting.balanceOf(address(linearVesting), derivativeTokenId),
            0,
            "derivative token: linear vesting balance mismatch"
        );

        // Base tokens have been transferred to the linear vesting module
        assertEq(underlyingToken.balanceOf(_alice), 0, "base token: alice balance mismatch");
        assertEq(underlyingToken.balanceOf(_recipient), 0, "base token: recipient balance mismatch");
        assertEq(
            underlyingToken.balanceOf(_owner),
            LOT_CAPACITY - BID_AMOUNT,
            "base token: owner balance mismatch"
        );
        assertEq(
            underlyingToken.balanceOf(address(auctionHouse)),
            0,
            "base token: auction house balance mismatch"
        );
        assertEq(
            underlyingToken.balanceOf(address(linearVesting)),
            BID_AMOUNT,
            "base token: linear vesting balance mismatch"
        );

        // Derivative token is not yet redeemable
        assertEq(linearVesting.redeemable(_recipient, derivativeTokenId), 0, "redeemable mismatch");

        // Derivative token cannot be transferred
        bytes memory err = abi.encodeWithSelector(LinearVesting.NotPermitted.selector);
        vm.expectRevert(err);
        vm.prank(_recipient);
        linearVesting.transfer(_alice, derivativeTokenId, BID_AMOUNT_OUT);
    }

    // bid
    // [X] given the auction is a batch auction
    //  [X] the bid is registered

    function test_bid_givenBatch()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenAuctionIsBatch
        givenAuctionHasStarted
        givenUserHasQuoteTokenBalance(BID_AMOUNT)
        givenAuctionHasBid
    {
        // Bid has been registered
        LocalSealedBidBatchAuction.EncryptedBid memory bid =
            localSealedBidBatchAuctionModule.getBidData(lotId, bidId);
        assertEq(bid.bidder, _alice, "bidder mismatch");
        assertEq(bid.recipient, _recipient, "recipient mismatch");
        assertEq(bid.referrer, _referrer, "referrer mismatch");
        assertEq(bid.amount, BID_AMOUNT, "amount mismatch");
        assertEq(
            bid.encryptedAmountOut,
            _encrypt(
                LocalSealedBidBatchAuction.Decrypt({amountOut: BID_AMOUNT_OUT, seed: BID_SEED})
            ),
            "encrypted amount out mismatch"
        );
    }

    // settle
    // [X] given the auction is a batch auction
    //  [X] the auction is settled, derivative tokens are minted to the bidder

    function test_settle_givenBatch()
        external
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenAuctionIsBatch
        givenAuctionHasStarted
        givenUserHasQuoteTokenBalance(BID_AMOUNT)
        givenAuctionHasBid
        givenAuctionHasEnded
        givenAuctionHasSettled
    {
        // Get the derivative id
        uint256 derivativeTokenId =
            linearVesting.computeId(underlyingTokenAddress, routingParams.derivativeParams);

        // Derivative tokens have been minted to the recipient
        assertEq(
            linearVesting.balanceOf(_alice, derivativeTokenId),
            0,
            "derivative token: alice balance mismatch"
        );
        assertEq(
            linearVesting.balanceOf(_recipient, derivativeTokenId),
            BID_AMOUNT_OUT,
            "derivative token: recipient balance mismatch"
        );
        assertEq(
            linearVesting.balanceOf(_owner, derivativeTokenId),
            0,
            "derivative token: owner balance mismatch"
        );
        assertEq(
            linearVesting.balanceOf(address(auctionHouse), derivativeTokenId),
            0,
            "derivative token: auction house balance mismatch"
        );
        assertEq(
            linearVesting.balanceOf(address(linearVesting), derivativeTokenId),
            0,
            "derivative token: linear vesting balance mismatch"
        );

        // Base tokens have been transferred to the linear vesting module
        assertEq(underlyingToken.balanceOf(_alice), 0, "base token: alice balance mismatch");
        assertEq(underlyingToken.balanceOf(_recipient), 0, "base token: recipient balance mismatch");
        assertEq(
            underlyingToken.balanceOf(_owner),
            LOT_CAPACITY - BID_AMOUNT_OUT,
            "base token: owner balance mismatch"
        ); // Returned to owner
        assertEq(
            underlyingToken.balanceOf(address(auctionHouse)),
            0,
            "base token: auction house balance mismatch"
        );
        assertEq(
            underlyingToken.balanceOf(address(linearVesting)),
            BID_AMOUNT,
            "base token: linear vesting balance mismatch"
        );

        // Derivative token is not yet redeemable
        assertEq(linearVesting.redeemable(_recipient, derivativeTokenId), 0, "redeemable mismatch");

        // Derivative token cannot be transferred
        bytes memory err = abi.encodeWithSelector(LinearVesting.NotPermitted.selector);
        vm.expectRevert(err);
        vm.prank(_recipient);
        linearVesting.transfer(_alice, derivativeTokenId, BID_AMOUNT_OUT);
    }
}
