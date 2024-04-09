// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {Auction} from "src/modules/Auction.sol";
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {ICallback} from "src/interfaces/ICallback.sol";

// Modules
import {toKeycode, Module} from "src/modules/Modules.sol";

contract CancelTest is Test, Permit2User {
    MockERC20 internal _baseToken;
    MockERC20 internal _quoteToken;
    MockAtomicAuctionModule internal _mockAuctionModule;

    AtomicAuctionHouse internal _auctionHouse;
    AuctionHouse.RoutingParams internal _routingParams;
    Auction.AuctionParams internal _auctionParams;

    uint96 internal _lotId;

    address internal constant _SELLER = address(0x1);

    address internal constant _PROTOCOL = address(0x2);
    string internal _infoHash = "";

    function setUp() external {
        _baseToken = new MockERC20("Base Token", "BASE", 18);
        _quoteToken = new MockERC20("Quote Token", "QUOTE", 18);

        _auctionHouse = new AtomicAuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _mockAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));

        _auctionHouse.installModule(_mockAuctionModule);

        _auctionParams = Auction.AuctionParams({
            start: uint48(block.timestamp),
            duration: uint48(1 days),
            capacityInQuote: false,
            capacity: 10e18,
            implParams: abi.encode("")
        });

        _routingParams = AuctionHouse.RoutingParams({
            auctionType: toKeycode("ATOM"),
            baseToken: _baseToken,
            quoteToken: _quoteToken,
            curator: address(0),
            callbacks: ICallback(address(0)),
            callbackData: abi.encode(""),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            wrapDerivative: false
        });
    }

    modifier whenLotIsCreated() {
        vm.prank(_SELLER);
        _lotId = _auctionHouse.auction(_routingParams, _auctionParams, _infoHash);
        _;
    }

    // cancel
    // [X] reverts if not the parent
    // [X] reverts if lot id is invalid
    // [X] reverts if lot is not active
    // [X] sets the lot to inactive

    function testReverts_whenCallerIsNotParent() external whenLotIsCreated {
        bytes memory err = abi.encodeWithSelector(Module.Module_OnlyParent.selector, address(this));
        vm.expectRevert(err);

        _mockAuctionModule.cancelAuction(_lotId);
    }

    function testReverts_whenLotIdInvalid() external {
        bytes memory err = abi.encodeWithSelector(Auction.Auction_InvalidLotId.selector, _lotId);
        vm.expectRevert(err);

        vm.prank(address(_auctionHouse));
        _mockAuctionModule.cancelAuction(_lotId);
    }

    function testReverts_whenLotIsInactive() external whenLotIsCreated {
        // Cancel once
        vm.prank(address(_auctionHouse));
        _mockAuctionModule.cancelAuction(_lotId);

        // Cancel again
        bytes memory err = abi.encodeWithSelector(Auction.Auction_MarketNotActive.selector, _lotId);
        vm.expectRevert(err);

        vm.prank(address(_auctionHouse));
        _mockAuctionModule.cancelAuction(_lotId);
    }

    function test_success() external whenLotIsCreated {
        assertTrue(_mockAuctionModule.isLive(_lotId), "before cancellation: isLive mismatch");

        vm.prank(address(_auctionHouse));
        _mockAuctionModule.cancelAuction(_lotId);

        // Get lot data from the module
        Auction.Lot memory lot = _mockAuctionModule.getLot(_lotId);
        assertEq(lot.conclusion, uint48(block.timestamp));
        assertEq(lot.capacity, 0);

        assertFalse(_mockAuctionModule.isLive(_lotId), "after cancellation: isLive mismatch");
    }
}
