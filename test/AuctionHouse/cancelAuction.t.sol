// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {AuctionHouse, Router} from "src/AuctionHouse.sol";
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

contract CancelAuctionTest is Test, Permit2User {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAtomicAuctionModule internal mockAuctionModule;

    AuctionHouse internal auctionHouse;
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    uint96 internal lotId;

    address internal auctionOwner = address(0x1);

    address internal protocol = address(0x2);
    address internal alice = address(0x3);

    uint256 internal constant LOT_CAPACITY = 10e18;

    uint256 internal constant PURCHASE_AMOUNT = 1e18;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(auctionOwner, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));

        auctionHouse.installModule(mockAuctionModule);

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("ATOM"),
            baseToken: baseToken,
            quoteToken: quoteToken,
            curator: address(0),
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            payoutData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode("")
        });
    }

    modifier whenLotIsCreated() {
        vm.prank(auctionOwner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    // cancel
    // [X] reverts if not the owner
    // [X] reverts if lot is not active
    // [X] reverts if lot id is invalid
    // [X] reverts if the lot is already cancelled
    // [X] given the auction is not prefunded
    //  [X] it sets the lot to inactive on the AuctionModule

    function testReverts_whenNotAuctionOwner() external whenLotIsCreated {
        bytes memory err =
            abi.encodeWithSelector(Auctioneer.NotAuctionOwner.selector, address(this));
        vm.expectRevert(err);

        auctionHouse.cancel(lotId);
    }

    function testReverts_whenUnauthorized(address user_) external whenLotIsCreated {
        vm.assume(user_ != auctionOwner);

        bytes memory err = abi.encodeWithSelector(Auctioneer.NotAuctionOwner.selector, user_);
        vm.expectRevert(err);

        vm.prank(user_);
        auctionHouse.cancel(lotId);
    }

    function testReverts_whenLotIdInvalid() external {
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);
    }

    function testReverts_whenLotIsInactive() external whenLotIsCreated {
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);

        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);
    }

    function test_givenCancelled_reverts() external whenLotIsCreated {
        // Cancel the lot
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, lotId);
        vm.expectRevert(err);

        // Call the function
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);
    }

    function test_success() external whenLotIsCreated {
        assertTrue(mockAuctionModule.isLive(lotId), "before cancellation: isLive mismatch");

        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);

        // Get lot data from the module
        (, uint48 lotConclusion,,,, uint256 lotCapacity,,) = mockAuctionModule.lotData(lotId);
        assertEq(lotConclusion, uint48(block.timestamp));
        assertEq(lotCapacity, 0);

        assertFalse(mockAuctionModule.isLive(lotId), "after cancellation: isLive mismatch");
    }

    // [X] given the auction is prefunded
    //  [X] it refunds the prefunded amount in payout tokens to the owner
    //  [X] given a purchase has been made
    //   [X] it refunds the remaining prefunded amount in payout tokens to the owner

    modifier givenLotIsPrefunded() {
        mockAuctionModule.setRequiredPrefunding(true);

        // Mint payout tokens to the owner
        baseToken.mint(auctionOwner, LOT_CAPACITY);

        // Approve transfer to the auction house
        vm.prank(auctionOwner);
        baseToken.approve(address(auctionHouse), LOT_CAPACITY);
        _;
    }

    modifier givenPurchase(uint256 amount_) {
        // Mint quote tokens to alice
        quoteToken.mint(alice, amount_);

        // Approve spending
        vm.prank(alice);
        quoteToken.approve(address(auctionHouse), amount_);

        // Create the purchase
        Router.PurchaseParams memory purchaseParams = Router.PurchaseParams({
            recipient: alice,
            referrer: address(0),
            lotId: lotId,
            amount: amount_,
            minAmountOut: amount_,
            auctionData: bytes(""),
            allowlistProof: bytes(""),
            permit2Data: bytes("")
        });

        vm.prank(alice);
        auctionHouse.purchase(purchaseParams);
        _;
    }

    function test_prefunded() external givenLotIsPrefunded whenLotIsCreated {
        // Check the owner's balance
        uint256 ownerBalance = baseToken.balanceOf(auctionOwner);

        // Cancel the lot
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);

        // Check the owner's balance
        assertEq(baseToken.balanceOf(auctionOwner), ownerBalance + LOT_CAPACITY);
    }

    function test_prefunded_givenPurchase()
        external
        givenLotIsPrefunded
        whenLotIsCreated
        givenPurchase(PURCHASE_AMOUNT)
    {
        // Check the owner's balance
        uint256 ownerBalance = baseToken.balanceOf(auctionOwner);

        // Cancel the lot
        vm.prank(auctionOwner);
        auctionHouse.cancel(lotId);

        // Check the owner's balance
        assertEq(baseToken.balanceOf(auctionOwner), ownerBalance + LOT_CAPACITY - PURCHASE_AMOUNT);
    }

    // [ ] given the auction is prefunded
    //  [ ] given a curator is set
    //   [ ] given a curator has not yet approved
    //    [ ] nothing happens
    //   [ ] it refunds the prefunded amount in payout tokens to the owner
}
