// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Interfaces
import {IFeeManager} from "../../src/interfaces/IFeeManager.sol";

// Libraries
import {Test} from "@forge-std-1.9.1/Test.sol";

// Mocks
import {MockAtomicAuctionModule} from "../modules/Auction/MockAtomicAuctionModule.sol";
import {Permit2User} from "../lib/permit2/Permit2User.sol";

// Auctions
import {AtomicAuctionHouse} from "../../src/AtomicAuctionHouse.sol";

// Modules
import {Keycode, keycodeFromVeecode} from "../../src/modules/Modules.sol";

contract AtomicSetFeeTest is Test, Permit2User {
    MockAtomicAuctionModule internal _mockAuctionModule;

    AtomicAuctionHouse internal _auctionHouse;

    address internal constant _OWNER = address(0x1);
    address internal constant _PROTOCOL = address(0x2);
    address internal constant _CURATOR = address(0x4);
    address internal constant _REFERRER = address(0x6);

    Keycode internal _auctionKeycode;

    uint48 internal constant _MAX_FEE = 100e2;

    function setUp() external {
        _auctionHouse = new AtomicAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _mockAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));
        _auctionKeycode = keycodeFromVeecode(_mockAuctionModule.VEECODE());

        vm.prank(_OWNER);
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
        _auctionHouse.setFee(_auctionKeycode, IFeeManager.FeeType.Protocol, 100);
    }

    function test_maxFee_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(IFeeManager.InvalidFee.selector);
        vm.expectRevert(err);

        vm.prank(_OWNER);
        _auctionHouse.setFee(_auctionKeycode, IFeeManager.FeeType.Protocol, _MAX_FEE + 1);
    }

    function test_protocolFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, _MAX_FEE));

        vm.prank(_OWNER);
        _auctionHouse.setFee(_auctionKeycode, IFeeManager.FeeType.Protocol, fee);

        // Validate
        (uint48 protocolFee, uint48 maxReferrerFee, uint48 maxCuratorFee) =
            _auctionHouse.fees(_auctionKeycode);
        assertEq(protocolFee, fee);
        assertEq(maxReferrerFee, 0);
        assertEq(maxCuratorFee, 0);
    }

    function test_maxReferrerFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, _MAX_FEE));

        vm.prank(_OWNER);
        _auctionHouse.setFee(_auctionKeycode, IFeeManager.FeeType.MaxReferrer, fee);

        // Validate
        (uint48 protocolFee, uint48 maxReferrerFee, uint48 maxCuratorFee) =
            _auctionHouse.fees(_auctionKeycode);
        assertEq(protocolFee, 0);
        assertEq(maxReferrerFee, fee);
        assertEq(maxCuratorFee, 0);
    }

    function test_curatorFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, _MAX_FEE));

        vm.prank(_OWNER);
        _auctionHouse.setFee(_auctionKeycode, IFeeManager.FeeType.MaxCurator, fee);

        // Validate
        (uint48 protocolFee, uint48 maxReferrerFee, uint48 maxCuratorFee) =
            _auctionHouse.fees(_auctionKeycode);
        assertEq(protocolFee, 0);
        assertEq(maxReferrerFee, 0);
        assertEq(maxCuratorFee, fee);
    }
}
