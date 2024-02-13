// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {MockAllowlist} from "test/modules/Auction/MockAllowlist.sol";
import {MockHook} from "test/modules/Auction/MockHook.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {AuctionHouse, FeeManager} from "src/AuctionHouse.sol";
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

contract CurateTest is Test, Permit2User {
    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockAtomicAuctionModule internal mockAuctionModule;
    MockAllowlist internal mockAllowlist;
    MockHook internal mockHook;

    AuctionHouse internal auctionHouse;
    Auctioneer.RoutingParams internal routingParams;
    Auction.AuctionParams internal auctionParams;

    address internal immutable protocol = address(0x2);
    address internal immutable curator = address(0x3);
    address internal immutable owner = address(0x4);

    uint256 internal constant LOT_CAPACITY = 10e18;
    uint48 internal constant CURATOR_MAX_FEE = 100;
    uint48 internal constant CURATOR_FEE = 90;

    uint96 internal lotId;

    function setUp() external {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        auctionHouse = new AuctionHouse(address(this), protocol, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));
        auctionHouse.installModule(mockAuctionModule);

        mockAllowlist = new MockAllowlist();
        mockHook = new MockHook(address(quoteToken), address(baseToken));

        auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp) + 1,
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: LOT_CAPACITY,
            implParams: abi.encode("")
        });

        routingParams = Auctioneer.RoutingParams({
            auctionType: toKeycode("ATOM"),
            baseToken: baseToken,
            quoteToken: quoteToken,
            curator: curator,
            hooks: IHooks(address(0)),
            allowlist: IAllowlist(address(0)),
            allowlistParams: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            infoHash: abi.encode("")
        });

        // Set the max curator fee
        auctionHouse.setFee(toKeycode("ATOM"), FeeManager.FeeType.MaxCurator, CURATOR_MAX_FEE);
    }

    // ===== Modifiers ===== //

    modifier givenCuratorIsZero() {
        routingParams.curator = address(0);
        _;
    }

    modifier givenOwnerHasBaseTokenBalance(uint256 amount_) {
        baseToken.mint(owner, amount_);

        // Approve spending of the payout tokens
        vm.prank(owner);
        baseToken.approve(address(auctionHouse), LOT_CAPACITY);
        _;
    }

    modifier givenLotHasStarted() {
        vm.warp(auctionParams.start + 1);
        _;
    }

    modifier givenLotHasConcluded() {
        vm.warp(auctionParams.start + auctionParams.duration + 1);
        _;
    }

    modifier givenLotHasBeenCancelled() {
        vm.prank(owner);
        auctionHouse.cancel(lotId);
        _;
    }

    modifier givenCuratorFeeIsSet() {
        vm.prank(curator);
        auctionHouse.setCuratorFee(toKeycode("ATOM"), CURATOR_FEE);
        _;
    }

    modifier givenLotIsPrefunded() {
        // Set the lot to be prefunded
        mockAuctionModule.setRequiredPrefunding(true);
        _;
    }

    modifier givenLotIsCreated() {
        vm.prank(owner);
        lotId = auctionHouse.auction(routingParams, auctionParams);
        _;
    }

    // ===== Tests ===== //

    // [X] when the lot id is invalid
    //  [X] it reverts
    // [X] given no curator is set
    //  [X] it reverts
    // [X] when the caller is not the lot curator
    //  [X] it reverts
    // [X] given the lot is already curated
    //  [X] it reverts
    // [X] given the lot has ended
    //  [X] it reverts
    // [X] given the lot has been cancelled
    //  [X] it reverts
    // [X] given no curator fee is set
    //  [X] it reverts
    // [X] given the lot is prefunded
    //  [X] it succeeds - the payout token is transferred to the auction house
    // [X] given the lot has not started
    //  [X] it succeeds
    // [X] it succeeds

    function test_whenLotIdIsInvalid() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidLotId.selector, lotId);
        vm.expectRevert(err);

        // Call
        vm.prank(curator);
        auctionHouse.curate(lotId);
    }

    function test_givenNoCuratorIsSet_whenCalledByCurator()
        public
        givenCuratorIsZero
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.NotPermitted.selector, curator);
        vm.expectRevert(err);

        // Call
        vm.prank(curator);
        auctionHouse.curate(lotId);
    }

    function test_givenNoCuratorIsSet_whenCalledByOwner()
        public
        givenCuratorIsZero
        givenLotIsCreated
        givenLotHasStarted
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.NotPermitted.selector, owner);
        vm.expectRevert(err);

        // Call
        vm.prank(owner);
        auctionHouse.curate(lotId);
    }

    function test_alreadyCurated()
        public
        givenLotIsCreated
        givenCuratorFeeIsSet
        givenLotHasStarted
    {
        // Curate
        vm.prank(curator);
        auctionHouse.curate(lotId);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
        vm.expectRevert(err);

        // Curate again
        vm.prank(curator);
        auctionHouse.curate(lotId);
    }

    function test_givenLotHasConcluded() public givenLotIsCreated givenLotHasConcluded {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(curator);
        auctionHouse.curate(lotId);
    }

    function test_givenLotHasBeenCancelled() public givenLotIsCreated givenLotHasBeenCancelled {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Auctioneer.InvalidState.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(curator);
        auctionHouse.curate(lotId);
    }

    function test_givenCuratorFeeNotSet() public givenLotIsCreated givenLotHasStarted {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(FeeManager.InvalidFee.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(curator);
        auctionHouse.curate(lotId);
    }

    function test_beforeStart() public givenLotIsCreated givenCuratorFeeIsSet {
        // Curate
        vm.prank(curator);
        auctionHouse.curate(lotId);

        // Verify
        (address lotCurator, bool lotCurated) = auctionHouse.lotCuration(lotId);
        assertEq(lotCurator, curator);
        assertTrue(lotCurated);

        // No curator fee is transferred to the auction house
        assertEq(baseToken.balanceOf(owner), 0);
        assertEq(baseToken.balanceOf(address(auctionHouse)), 0);
        assertEq(baseToken.balanceOf(curator), 0);
    }

    function test_afterStart() public givenLotIsCreated givenCuratorFeeIsSet givenLotHasStarted {
        // Curate
        vm.prank(curator);
        auctionHouse.curate(lotId);

        // Verify
        (address lotCurator, bool lotCurated) = auctionHouse.lotCuration(lotId);
        assertEq(lotCurator, curator);
        assertTrue(lotCurated);

        // No curator fee is transferred to the auction house
        assertEq(baseToken.balanceOf(owner), 0);
        assertEq(baseToken.balanceOf(address(auctionHouse)), 0);
        assertEq(baseToken.balanceOf(curator), 0);
    }

    function test_givenLotIsPrefunded()
        public
        givenOwnerHasBaseTokenBalance(LOT_CAPACITY)
        givenLotIsPrefunded
        givenLotIsCreated
        givenCuratorFeeIsSet
        givenLotHasStarted
    {
        // Calculate the curator fee
        uint256 curatorMaxFee = (LOT_CAPACITY * CURATOR_FEE) / 1e5;

        // Mint the base token to the owner
        baseToken.mint(owner, curatorMaxFee);

        // Approve spending of the payout tokens
        vm.prank(owner);
        baseToken.approve(address(auctionHouse), curatorMaxFee);

        // Curate
        vm.prank(curator);
        auctionHouse.curate(lotId);

        // Verify
        (address lotCurator, bool lotCurated) = auctionHouse.lotCuration(lotId);
        assertEq(lotCurator, curator);
        assertTrue(lotCurated);

        // Maximum curator fee is transferred to the auction house
        assertEq(baseToken.balanceOf(owner), 0, "base token: owner balance mismatch");
        assertEq(
            baseToken.balanceOf(address(auctionHouse)),
            LOT_CAPACITY + curatorMaxFee,
            "base token: auction house balance mismatch"
        );
        assertEq(baseToken.balanceOf(curator), 0, "base token: curator balance mismatch");
    }
}
