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

contract SetFeeTest is Test, Permit2User {
    MockAtomicAuctionModule internal mockAuctionModule;

    AuctionHouse internal auctionHouse;

    address internal immutable protocol = address(0x2);
    address internal immutable curator = address(0x3);
    address internal immutable referrer = address(0x4);

    Keycode internal auctionKeycode = toKeycode("ATOM");

    uint48 internal constant MAX_FEE = 1e5;

    function setUp() external {
        auctionHouse = new AuctionHouse(address(this), protocol, _PERMIT2_ADDRESS);
        mockAuctionModule = new MockAtomicAuctionModule(address(auctionHouse));
        auctionHouse.installModule(mockAuctionModule);
    }

    // [X] when called by a non-owner
    //  [X] it reverts
    // [X] when the fee is more than the maximum
    //  [X] it reverts
    // [X] when the fee type is protocol
    //  [X] it sets the protocol fee
    // [X] when the fee type is referrer
    //  [X] it sets the referrer fee
    // [X] when the fee type is curator
    //  [X] it sets the maximum curator fee

    function test_unauthorized() public {
        // Expect reverts
        vm.expectRevert("UNAUTHORIZED");

        vm.prank(curator);
        auctionHouse.setFee(auctionKeycode, FeeManager.FeeType.Protocol, 100);
    }

    function test_maxFee_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(FeeManager.InvalidFee.selector);
        vm.expectRevert(err);

        auctionHouse.setFee(auctionKeycode, FeeManager.FeeType.Protocol, MAX_FEE + 1);
    }

    function test_protocolFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, MAX_FEE));

        auctionHouse.setFee(auctionKeycode, FeeManager.FeeType.Protocol, fee);

        // Validate
        (uint48 protocolFee, uint48 referrerFee, uint48 maxCuratorFee) =
            auctionHouse.fees(auctionKeycode);
        assertEq(protocolFee, fee);
        assertEq(referrerFee, 0);
        assertEq(maxCuratorFee, 0);
    }

    function test_referrerFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, MAX_FEE));

        auctionHouse.setFee(auctionKeycode, FeeManager.FeeType.Referrer, fee);

        // Validate
        (uint48 protocolFee, uint48 referrerFee, uint48 maxCuratorFee) =
            auctionHouse.fees(auctionKeycode);
        assertEq(protocolFee, 0);
        assertEq(referrerFee, fee);
        assertEq(maxCuratorFee, 0);
    }

    function test_curatorFee(uint48 fee_) public {
        uint48 fee = uint48(bound(fee_, 0, MAX_FEE));

        auctionHouse.setFee(auctionKeycode, FeeManager.FeeType.MaxCurator, fee);

        // Validate
        (uint48 protocolFee, uint48 referrerFee, uint48 maxCuratorFee) =
            auctionHouse.fees(auctionKeycode);
        assertEq(protocolFee, 0);
        assertEq(referrerFee, 0);
        assertEq(maxCuratorFee, fee);
    }
}
