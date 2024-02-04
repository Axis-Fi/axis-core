// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ClonesWithImmutableArgs} from "src/lib/clones/ClonesWithImmutableArgs.sol";
import {StringHelper} from "test/lib/String.sol";

import {SoulboundCloneERC20} from "src/modules/derivatives/SoulboundCloneERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract SoulboundCloneERC20Test is Test {
    using ClonesWithImmutableArgs for address;
    using StringHelper for string;

    SoulboundCloneERC20 internal _IMPLEMENTATION;
    SoulboundCloneERC20 internal clonedImplementation;
    MockERC20 internal underlyingToken;

    string internal tokenName = "Test Token";
    string internal tokenSymbol = "TEST";
    uint8 internal tokenDecimals = 18;
    uint256 internal tokenSalt = 222;
    uint48 internal tokenExpiry = 1_705_055_144;
    uint256 internal tokenNameLength;
    uint256 internal tokenSymbolLength;

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal owner = address(0x3);

    function setUp() public {
        _IMPLEMENTATION = new SoulboundCloneERC20();

        underlyingToken = new MockERC20("Underlying Token", "UNDERLYING", 18);

        tokenNameLength = bytes(tokenName).length;
        tokenSymbolLength = bytes(tokenSymbol).length;
    }

    modifier givenCloneIsDeployed() {
        bytes memory tokenData = abi.encodePacked(
            bytes32(bytes(tokenName)),
            bytes32(bytes(tokenSymbol)),
            uint8(tokenDecimals),
            uint64(tokenExpiry),
            owner,
            address(underlyingToken)
        );
        address clonedContract = address(_IMPLEMENTATION).clone3(tokenData, bytes32(tokenSalt));
        clonedImplementation = SoulboundCloneERC20(clonedContract);
        _;
    }

    // [X] deployment
    //  [X] the name, symbol and decimals are set correctly
    // [X] transfer
    //  [X] it reverts
    // [X] transferFrom
    //  [X] it reverts
    // [X] approval
    //  [X] it succeeds
    // [X] mint
    //  [X] it reverts if not called by the owner
    //  [X] it succeeds if called by the owner
    // [X] burn
    //  [X] it reverts if not called by the owner
    //  [X] it succeeds if called by the owner

    function test_deployment() public givenCloneIsDeployed {
        assertEq(clonedImplementation.name().trim(0, tokenNameLength), tokenName, "name mismatch");
        assertEq(
            clonedImplementation.symbol().trim(0, tokenSymbolLength), tokenSymbol, "symbol mismatch"
        );
        assertEq(clonedImplementation.decimals(), tokenDecimals, "decimals mismatch");
        assertEq(clonedImplementation.expiry(), tokenExpiry, "expiry mismatch");
        assertEq(clonedImplementation.owner(), owner, "owner mismatch");
        assertEq(
            address(clonedImplementation.underlying()),
            address(underlyingToken),
            "underlying mismatch"
        );

        // Ensure it is deterministic
        assertEq(
            ClonesWithImmutableArgs.addressOfClone3(bytes32(tokenSalt)),
            address(clonedImplementation)
        );
    }

    function test_approval_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Approve tokens
        vm.prank(owner);
        clonedImplementation.approve(bob, 100);
    }

    function test_approval_notOwner_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Approve tokens
        vm.prank(alice);
        clonedImplementation.approve(bob, 100);
    }

    function test_transfer_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(owner);
        clonedImplementation.mint(address(this), 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(owner);
        clonedImplementation.transfer(bob, 100);
    }

    function test_transfer_notOwner_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(owner);
        clonedImplementation.mint(alice, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(alice);
        clonedImplementation.transfer(bob, 100);
    }

    function test_transferFrom_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(owner);
        clonedImplementation.mint(address(this), 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(owner);
        clonedImplementation.transferFrom(address(this), bob, 100);
    }

    function test_transferFrom_notOwner_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(owner);
        clonedImplementation.mint(alice, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(alice);
        clonedImplementation.transferFrom(alice, bob, 100);
    }

    function test_mint() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(owner);
        clonedImplementation.mint(alice, 100);

        // Check balances
        assertEq(clonedImplementation.balanceOf(alice), 100);
    }

    function test_mint_notOwner_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Mint tokens
        vm.prank(alice);
        clonedImplementation.mint(alice, 100);
    }

    function test_burn() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(owner);
        clonedImplementation.mint(alice, 100);

        // Burn tokens
        vm.prank(owner);
        clonedImplementation.burn(alice, 100);

        // Check balances
        assertEq(clonedImplementation.balanceOf(alice), 0);
    }

    function test_burn_notOwner_reverts() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(owner);
        clonedImplementation.mint(alice, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Burn tokens
        vm.prank(alice);
        clonedImplementation.burn(alice, 100);
    }
}
