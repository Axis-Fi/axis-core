// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IPermit2} from "src/lib/permit2/interfaces/IPermit2.sol";

// Mocks
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {AuctionHouse, Router, FeeManager} from "src/AuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {IHooks, IAllowlist, Auctioneer} from "src/bases/Auctioneer.sol";

// Modules
import {
    Keycode,
    toKeycode,
    Veecode,
    wrapVeecode,
    fromVeecode,
    WithModules,
    Module
} from "src/modules/Modules.sol";

contract SetProtocolTest is Test, Permit2User {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAtomicAuctionModule internal mockAuctionModule;

    AuctionHouse internal auctionHouse;

    address internal immutable protocol = address(0x2);
    address internal immutable curator = address(0x3);
    address internal immutable referrer = address(0x4);
    address internal immutable auctionOwner = address(0x5);
    address internal immutable recipient = address(0x6);
    address internal immutable newProtocol = address(0x7);

    uint256 internal aliceKey;
    address internal alice;

    uint96 internal lotId;

    uint256 internal constant LOT_CAPACITY = 10e18;

    uint256 internal constant AMOUNT_IN = 1e18;
    uint256 internal AMOUNT_OUT;
    uint256 internal curatorActualFee;
    uint256 internal curatorMaxPotentialFee;

    uint48 internal constant CURATOR_MAX_FEE = 100;
    uint48 internal constant CURATOR_FEE = 90;

    uint48 internal referrerFee;
    uint48 internal protocolFee;

    uint256 internal amountInLessFee;
    uint256 internal amountInReferrerFee;
    uint256 internal amountInProtocolFee;

    Keycode internal auctionType = toKeycode("ATOM");
    string internal INFO_HASH = "";

    // Function parameters (can be modified)
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;
    Router.PurchaseParams internal purchaseParams;
    uint256 internal approvalNonce;
    bytes internal approvalSignature;
    uint48 internal approvalDeadline;
    uint256 internal derivativeTokenId;
    bytes internal allowlistProof;

    function setUp() external {
        aliceKey = _getRandomUint256();
        alice = vm.addr(aliceKey);

        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(address(this), protocol, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: auctionType,
            baseToken: baseToken,
            quoteToken: quoteToken,
            curator: address(0),
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode("")
        });

        // Install the auction module
        auctionHouse.installModule(mockAuctionModule);

        // Create an auction
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams, INFO_HASH);

        // Fees
        referrerFee = 1000;
        protocolFee = 2000;
        auctionHouse.setFee(auctionType, FeeManager.FeeType.Protocol, protocolFee);
        auctionHouse.setFee(auctionType, FeeManager.FeeType.Referrer, referrerFee);
        auctionHouse.setFee(auctionType, FeeManager.FeeType.MaxCurator, CURATOR_MAX_FEE);
        curatorMaxPotentialFee = CURATOR_FEE * LOT_CAPACITY / 1e5;

        amountInReferrerFee = (AMOUNT_IN * referrerFee) / 1e5;
        amountInProtocolFee = (AMOUNT_IN * protocolFee) / 1e5;
        amountInLessFee = AMOUNT_IN - amountInReferrerFee - amountInProtocolFee;

        // 1:1 exchange rate
        AMOUNT_OUT = amountInLessFee;

        // Purchase parameters
        purchaseParams = Router.PurchaseParams({
            recipient: recipient,
            referrer: referrer,
            lotId: lotId,
            amount: AMOUNT_IN,
            minAmountOut: AMOUNT_OUT,
            auctionData: bytes(""),
            allowlistProof: allowlistProof,
            permit2Data: bytes("")
        });
    }

    // ===== Modifiers ===== //

    modifier givenProtocolAddressIsSet(address protocol_) {
        auctionHouse.setProtocol(protocol_);
        _;
    }

    modifier givenPurchase(uint256 amount_) {
        // Mint base tokens
        baseToken.mint(auctionOwner, LOT_CAPACITY);

        // Approve spending
        vm.prank(auctionOwner);
        baseToken.approve(address(auctionHouse), LOT_CAPACITY);

        // Mint quote tokens
        quoteToken.mint(alice, amount_);

        // Approve spending
        vm.prank(alice);
        quoteToken.approve(address(auctionHouse), amount_);

        // Purchase
        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
        _;
    }

    // ===== Tests ===== //

    // [X] when caller is not the owner
    //  [X] it reverts
    // [X] it sets the protocol address

    function test_unauthorized() public {
        // Expect revert
        vm.expectRevert("UNAUTHORIZED");

        // Call
        vm.prank(alice);
        auctionHouse.setProtocol(newProtocol);
    }

    function test_whenAddressIsNew()
        public
        givenProtocolAddressIsSet(newProtocol)
        givenPurchase(AMOUNT_IN)
    {
        // Previous balance
        uint256 previousBalance = quoteToken.balanceOf(newProtocol);

        // Claim rewards
        // As the protocol address is private, we cannot check that it was changed. But we can check that rewards were accrued.
        vm.prank(newProtocol);
        auctionHouse.claimRewards(address(quoteToken));

        // Check new balance
        assertEq(quoteToken.balanceOf(newProtocol), previousBalance + amountInProtocolFee);

        // Check rewards
        assertEq(auctionHouse.rewards(newProtocol, quoteToken), 0);
    }
}
