// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {ClonesWithImmutableArgs} from "src/lib/clones/ClonesWithImmutableArgs.sol";
import {StringHelper} from "test/lib/String.sol";

import {SoulboundCloneERC20} from "src/modules/derivatives/SoulboundCloneERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract SoulboundCloneERC20Test is Test {
    using ClonesWithImmutableArgs for address;
    using StringHelper for string;

    SoulboundCloneERC20 internal _implementation;
    SoulboundCloneERC20 internal _clonedImplementation;
    MockERC20 internal _underlyingToken;

    string internal _tokenName = "Test Token";
    string internal _tokenSymbol = "TEST";
    uint8 internal _tokenDecimals = 18;
    uint256 internal _tokenSalt = 222;
    uint48 internal _tokenExpiry = 1_705_055_144;
    uint256 internal _tokenNameLength;
    uint256 internal _tokenSymbolLength;

    address internal constant _ALICE = address(0x1);
    address internal constant _BOB = address(0x2);
    address internal constant _OWNER = address(0x3);

    function setUp() public {
        _implementation = new SoulboundCloneERC20();

        _underlyingToken = new MockERC20("Underlying Token", "UNDERLYING", 18);

        _tokenNameLength = bytes(_tokenName).length;
        _tokenSymbolLength = bytes(_tokenSymbol).length;
    }

    modifier givenCloneIsDeployed() {
        bytes memory tokenData = abi.encodePacked(
            bytes32(bytes(_tokenName)),
            bytes32(bytes(_tokenSymbol)),
            uint8(_tokenDecimals),
            uint64(_tokenExpiry),
            _OWNER,
            address(_underlyingToken)
        );
        address clonedContract = address(_implementation).clone3(tokenData, bytes32(_tokenSalt));
        _clonedImplementation = SoulboundCloneERC20(clonedContract);
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
    //  [X] it reverts if not called by the _OWNER
    //  [X] it succeeds if called by the _OWNER
    // [X] burn
    //  [X] it reverts if not called by the _OWNER
    //  [X] it succeeds if called by the _OWNER

    function test_deployment() public givenCloneIsDeployed {
        assertEq(
            _clonedImplementation.name().trim(0, _tokenNameLength), _tokenName, "name mismatch"
        );
        assertEq(
            _clonedImplementation.symbol().trim(0, _tokenSymbolLength),
            _tokenSymbol,
            "symbol mismatch"
        );
        assertEq(_clonedImplementation.decimals(), _tokenDecimals, "decimals mismatch");
        assertEq(_clonedImplementation.expiry(), _tokenExpiry, "expiry mismatch");
        assertEq(_clonedImplementation.owner(), _OWNER, "_OWNER mismatch");
        assertEq(
            address(_clonedImplementation.underlying()),
            address(_underlyingToken),
            "underlying mismatch"
        );

        // Ensure it is deterministic
        assertEq(
            ClonesWithImmutableArgs.addressOfClone3(bytes32(_tokenSalt)),
            address(_clonedImplementation)
        );
    }

    function test_approval_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Approve tokens
        vm.prank(_OWNER);
        _clonedImplementation.approve(_BOB, 100);
    }

    function test_approval_notOwner_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Approve tokens
        vm.prank(_ALICE);
        _clonedImplementation.approve(_BOB, 100);
    }

    function test_transfer_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(_OWNER);
        _clonedImplementation.mint(address(this), 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(_OWNER);
        _clonedImplementation.transfer(_BOB, 100);
    }

    function test_transfer_notOwner_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(_OWNER);
        _clonedImplementation.mint(_ALICE, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(_ALICE);
        _clonedImplementation.transfer(_BOB, 100);
    }

    function test_transferFrom_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(_OWNER);
        _clonedImplementation.mint(address(this), 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(_OWNER);
        _clonedImplementation.transferFrom(address(this), _BOB, 100);
    }

    function test_transferFrom_notOwner_reverts() public givenCloneIsDeployed {
        // Mint to the caller
        vm.prank(_OWNER);
        _clonedImplementation.mint(_ALICE, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Transfer tokens
        vm.prank(_ALICE);
        _clonedImplementation.transferFrom(_ALICE, _BOB, 100);
    }

    function test_mint() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(_OWNER);
        _clonedImplementation.mint(_ALICE, 100);

        // Check balances
        assertEq(_clonedImplementation.balanceOf(_ALICE), 100);
    }

    function test_mint_notOwner_reverts() public givenCloneIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Mint tokens
        vm.prank(_ALICE);
        _clonedImplementation.mint(_ALICE, 100);
    }

    function test_burn() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(_OWNER);
        _clonedImplementation.mint(_ALICE, 100);

        // Burn tokens
        vm.prank(_OWNER);
        _clonedImplementation.burn(_ALICE, 100);

        // Check balances
        assertEq(_clonedImplementation.balanceOf(_ALICE), 0);
    }

    function test_burn_notOwner_reverts() public givenCloneIsDeployed {
        // Mint tokens
        vm.prank(_OWNER);
        _clonedImplementation.mint(_ALICE, 100);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(SoulboundCloneERC20.NotPermitted.selector);
        vm.expectRevert(err);

        // Burn tokens
        vm.prank(_ALICE);
        _clonedImplementation.burn(_ALICE, 100);
    }
}
