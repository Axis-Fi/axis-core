// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

// Mocks
import {MockAtomicAuctionModule} from "test/modules/Auction/MockAtomicAuctionModule.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

// Auctions
import {AuctionHouse, FeeManager} from "src/AuctionHouse.sol";

// Modules
import {Keycode, toKeycode} from "src/modules/Modules.sol";

contract SetFeeTest is Test, Permit2User {
    MockAtomicAuctionModule internal _mockAuctionModule;

    AuctionHouse internal _auctionHouse;

    address internal immutable _PROTOCOL = address(0x2);
    address internal immutable _CURATOR = address(0x3);
    address internal immutable _REFERRER = address(0x4);

    Keycode internal _auctionKeycode = toKeycode("ATOM");

    uint48 internal constant _MAX_FEE = 1e5;

    function setUp() external {
        _auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _mockAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));
        _auctionHouse.installModule(_mockAuctionModule);
    }

    // [X] when called by a non-owner
    //  [X] it reverts
    // [X] when the fee is more than the maximum
    //  [X] it reverts
    // [X] when the fee type is _PROTOCOL
    //  [X] it sets the _PROTOCOL fee
    // [X] when the fee type is _REFERRER
    //  [X] it sets the _REFERRER fee
    // [X] when the fee type is _CURATOR
    //  [X] it sets the maximum _CURATOR fee

    function test_unauthorized() public {
        // Expect reverts
        vm.expectRevert("UNAUTHORIZED");

        vm.prank(_CURATOR);
        _auctionHouse.setFee(_auctionKeycode, FeeManager.FeeType.Protocol, 100);
    }

    function test_maxFee_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(FeeManager.InvalidFee.selector);
        vm.expectRevert(err);

        _auctionHouse.setFee(_auctionKeycode, FeeManager.FeeType.Protocol, _MAX_FEE + 1);
    }

    function test_protocolFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, _MAX_FEE));

        _auctionHouse.setFee(_auctionKeycode, FeeManager.FeeType.Protocol, fee);

        // Validate
        (uint48 protocolFee, uint48 referrerFee, uint48 maxCuratorFee) =
            _auctionHouse.fees(_auctionKeycode);
        assertEq(protocolFee, fee);
        assertEq(referrerFee, 0);
        assertEq(maxCuratorFee, 0);
    }

    function test_referrerFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, _MAX_FEE));

        _auctionHouse.setFee(_auctionKeycode, FeeManager.FeeType.Referrer, fee);

        // Validate
        (uint48 protocolFee, uint48 referrerFee, uint48 maxCuratorFee) =
            _auctionHouse.fees(_auctionKeycode);
        assertEq(protocolFee, 0);
        assertEq(referrerFee, fee);
        assertEq(maxCuratorFee, 0);
    }

    function test_curatorFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, _MAX_FEE));

        _auctionHouse.setFee(_auctionKeycode, FeeManager.FeeType.MaxCurator, fee);

        // Validate
        (uint48 protocolFee, uint48 referrerFee, uint48 maxCuratorFee) =
            _auctionHouse.fees(_auctionKeycode);
        assertEq(protocolFee, 0);
        assertEq(referrerFee, 0);
        assertEq(maxCuratorFee, fee);
    }
}
