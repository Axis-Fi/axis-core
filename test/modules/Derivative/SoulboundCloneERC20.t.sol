// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ClonesWithImmutableArgs} from "src/lib/clones/ClonesWithImmutableArgs.sol";

import {SoulboundCloneERC20} from "src/modules/derivatives/SoulboundCloneERC20.sol";

contract SoulboundCloneERC20Test is Test {
    using ClonesWithImmutableArgs for address;

    SoulboundCloneERC20 internal clone;
    SoulboundCloneERC20 internal implementation;

    string internal tokenName = "Test Token";
    string internal tokenSymbol = "TEST";
    uint8 internal tokenDecimals = 18;
    uint256 internal tokenSalt = 222;

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal owner = address(0x3);

    function setUp() public {
        clone = new SoulboundCloneERC20();
    }

    modifier givenCloneIsDeployed() {
        bytes memory tokenData = abi.encodePacked(
            bytes32(bytes(tokenName)), bytes32(bytes(tokenSymbol)), uint8(tokenDecimals), owner
        );
        address clonedContract = address(clone).clone3(tokenData, bytes32(tokenSalt));
        implementation = SoulboundCloneERC20(clonedContract);
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
        assertEq(bytes32(bytes(implementation.name())), bytes32(bytes(tokenName))); // Needs conversion due to bytes encoding
        assertEq(bytes32(bytes(implementation.symbol())), bytes32(bytes(tokenSymbol))); // Needs conversion due to bytes encoding
        assertEq(implementation.decimals(), tokenDecimals);
        assertEq(implementation.owner(), owner);

        // Ensure it is deterministic
        assertEq(
            ClonesWithImmutableArgs.addressOfClone3(bytes32(tokenSalt)), address(implementation)
        );
    }

    function test_approval_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Approve tokens
        vm.prank(owner);
        implementation.approve(bob, 100);
    }

    function test_approval_notOwner_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Approve tokens
        vm.prank(alice);
        implementation.approve(bob, 100);
    }

    function test_transfer_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(owner);
        implementation.mint(address(this), 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(owner);
        implementation.transfer(bob, 100);
    }

    function test_transfer_notOwner_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(owner);
        implementation.mint(alice, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(alice);
        implementation.transfer(bob, 100);
    }

    function test_transferFrom_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(owner);
        implementation.mint(address(this), 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(owner);
        implementation.transferFrom(address(this), bob, 100);
    }

    function test_transferFrom_notOwner_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(owner);
        implementation.mint(alice, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(alice);
        implementation.transferFrom(alice, bob, 100);
    }

    function test_mint() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(owner);
        implementation.mint(alice, 100);

        // Check balances
        assertEq(implementation.balanceOf(alice), 100);
    }

    function test_mint_notOwner_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Mint tokens
        vm.prank(alice);
        implementation.mint(alice, 100);
    }

    function test_burn() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(owner);
        implementation.mint(alice, 100);

        // Burn tokens
        vm.prank(owner);
        implementation.burn(alice, 100);

        // Check balances
        assertEq(implementation.balanceOf(alice), 0);
    }

    function test_burn_notOwner_reverts() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(owner);
        implementation.mint(alice, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Burn tokens
        vm.prank(alice);
        implementation.burn(alice, 100);
    }
}
