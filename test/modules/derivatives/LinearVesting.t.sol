// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {SoulboundCloneERC20} from "src/modules/derivatives/SoulboundCloneERC20.sol";
import {AuctionHouse} from "src/AuctionHouse.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";

contract LinearVestingTest is Test, Permit2User {
    address internal _clone;

    address internal constant _owner = address(0x1);
    address internal constant _protocol = address(0x2);
    address internal constant _alice = address(0x3);

    MockERC20 internal underlyingToken;
    address internal underlyingTokenAddress;

    AuctionHouse internal auctionHouse;
    LinearVesting internal linearVesting;

    LinearVesting.VestingParams internal vestingParams;
    bytes internal vestingParamsBytes;
    uint48 internal constant vestingStart = 1_000_100;
    uint48 internal constant vestingExpiry = 1_000_200;
    uint48 internal constant vestingEnd = 1_000_300;

    uint256 internal constant AMOUNT = 1e18;

    uint256 internal derivativeTokenId;
    address internal derivativeWrappedAddress;

    function setUp() public {
        // Wrap to reasonable timestamp
        vm.warp(1_000_000);

        _clone = address(new SoulboundCloneERC20());

        underlyingToken = new MockERC20("Underlying", "UNDERLYING", 18);
        underlyingTokenAddress = address(underlyingToken);

        auctionHouse = new AuctionHouse(_protocol, _PERMIT2_ADDRESS);
        linearVesting = new LinearVesting(address(auctionHouse), _clone);
        auctionHouse.installModule(linearVesting);

        vestingParams = LinearVesting.VestingParams({
            start: vestingStart,
            expiry: vestingExpiry,
            end: vestingEnd
        });
        vestingParamsBytes = abi.encode(vestingParams);
    }

    // ========== MODIFIERS ========== //

    modifier givenVestingParamsAreInvalid() {
        vestingParamsBytes = abi.encode("junk");
        _;
    }

    modifier whenUnderlyingTokenIsZero() {
        underlyingTokenAddress = address(0);
        _;
    }

    modifier whenStartTimestampIsZero() {
        vestingParams.start = 0;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenExpiryTimestampIsZero() {
        vestingParams.expiry = 0;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenEndTimestampIsZero() {
        vestingParams.end = 0;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenStartAndExpiryTimestampsAreTheSame() {
        vestingParams.expiry = vestingParams.start;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenExpiryAndEndTimestampsAreTheSame() {
        vestingParams.end = vestingParams.expiry;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenStartAndEndTimestampsAreTheSame() {
        vestingParams.end = vestingParams.start;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenStartTimestampIsAfterExpiryTimestamp() {
        vestingParams.start = vestingParams.expiry + 1;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenExpiryTimestampIsAfterEndTimestamp() {
        vestingParams.expiry = vestingParams.end + 1;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenStartTimestampIsAfterEndTimestamp() {
        vestingParams.start = vestingParams.end + 1;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenStartTimestampIsBeforeCurrentTimestamp() {
        vestingParams.start = uint48(block.timestamp) - 1;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenExpiryTimestampIsBeforeCurrentTimestamp() {
        vestingParams.expiry = uint48(block.timestamp) - 1;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenEndTimestampIsBeforeCurrentTimestamp() {
        vestingParams.end = uint48(block.timestamp) - 1;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenVestingParamsAreChanged() {
        vestingParams.start = vestingParams.start + 1;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenUnderlyingTokenIsChanged() {
        underlyingToken = new MockERC20("Underlying", "UNDERLYING", 18);
        underlyingTokenAddress = address(underlyingToken);
        _;
    }

    modifier givenDerivativeIsDeployed() {
        (derivativeTokenId, derivativeWrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);

        assertTrue(derivativeTokenId > 0);
        assertTrue(derivativeWrappedAddress == address(0));
        _;
    }

    modifier givenWrappedDerivativeIsDeployed() {
        (derivativeTokenId, derivativeWrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        assertTrue(derivativeTokenId > 0);
        assertTrue(derivativeWrappedAddress != address(0));
        _;
    }

    modifier givenParentHasUnderlyingTokenBalance(uint256 balance_) {
        underlyingToken.mint(address(auctionHouse), balance_);
        _;
    }

    // ========== TESTS ========== //

    // deploy
    // [X] when the vesting params are in the incorrect format
    //  [X] it reverts
    // [X] when the underlying token is 0
    //  [X] it reverts
    // [X] when the start timestamp is 0
    //  [X] it reverts
    // [X] when the expiry timestamp is 0
    //  [X] it reverts
    // [X] when the end timestamp is 0
    //  [X] it reverts
    // [X] when the start and expiry timestamps are the same
    //  [X] it reverts
    // [X] when the expiry and end timestamps are the same
    //  [X] it reverts
    // [X] when the start and end timestamps are the same
    //  [X] it reverts
    // [X] when the start timestamp is after the expiry timestamp
    //  [X] it reverts
    // [X] when the expiry timestamp is after the end timestamp
    //  [X] it reverts
    // [X] when the start timestamp is after the end timestamp
    //  [X] it reverts
    // [X] when the start timestamp is before the current timestamp
    //  [X] it reverts
    // [X] when the expiry timestamp is before the current timestamp
    //  [X] it reverts
    // [X] when the end timestamp is before the current timestamp
    //  [X] it reverts
    // [X] given the token is already deployed
    //  [X] given the wrapped token is already deployed
    //   [X] it returns the same token id and wrapped token address
    //  [X] it returns the token id and deploys the wrapped token
    // [X] given the token is not already deployed
    //  [X] it deploys the token and wrapped token
    // [X] when the caller is not the parent
    //  [X] it succeeds
    // [ ] when the parameters change
    //  [ ] it returns a different token id

    function test_deploy_incorrectParams_reverts() public givenVestingParamsAreInvalid {
        // Expect revert
        vm.expectRevert();

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_underlyingTokenIsZero_reverts() public whenUnderlyingTokenIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_startTimestampIsZero_reverts() public whenStartTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_expiryTimestampIsZero_reverts() public whenExpiryTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_endTimestampIsZero_reverts() public whenEndTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_startAndExpiryTimestampsAreTheSame_reverts()
        public
        whenStartAndExpiryTimestampsAreTheSame
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_expiryAndEndTimestampsAreTheSame_reverts()
        public
        whenExpiryAndEndTimestampsAreTheSame
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_startAndEndTimestampsAreTheSame_reverts()
        public
        whenStartAndEndTimestampsAreTheSame
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_startTimestampIsAfterExpiryTimestamp_reverts()
        public
        whenStartTimestampIsAfterExpiryTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_expiryTimestampIsAfterEndTimestamp_reverts()
        public
        whenExpiryTimestampIsAfterEndTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_startTimestampIsAfterEndTimestamp_reverts()
        public
        whenStartTimestampIsAfterEndTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_startTimestampIsBeforeCurrentTimestamp_reverts()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_expiryTimestampIsBeforeCurrentTimestamp_reverts()
        public
        whenExpiryTimestampIsBeforeCurrentTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_endTimestampIsBeforeCurrentTimestamp_reverts()
        public
        whenEndTimestampIsBeforeCurrentTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);
    }

    function test_deploy_derivativeDeployed_wrappedDerivativeDeployed()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertEq(wrappedAddress, derivativeWrappedAddress);
    }

    function test_deploy_derivativeDeployed_wrappedDerivativeNotDeployed()
        public
        givenDerivativeIsDeployed
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertTrue(wrappedAddress != address(0));
    }

    function test_deploy() public {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertTrue(tokenId > 0);
        assertTrue(wrappedAddress != address(0));
    }

    function test_deploy_notParent() public {
        // Call
        vm.prank(_alice);
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertTrue(tokenId > 0);
        assertTrue(wrappedAddress != address(0));
    }

    function test_deploy_notParent_derivativeDeployed_wrappedDerivativeDeployed()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(_alice);
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertEq(wrappedAddress, derivativeWrappedAddress);
    }

    function test_deploy_differentVestingParams()
        public
        givenWrappedDerivativeIsDeployed
        whenVestingParamsAreChanged
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertFalse(tokenId == derivativeTokenId);
        assertFalse(wrappedAddress == derivativeWrappedAddress);
    }

    function test_deploy_differentUnderlyingToken()
        public
        givenWrappedDerivativeIsDeployed
        whenUnderlyingTokenIsChanged
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertFalse(tokenId == derivativeTokenId);
        assertFalse(wrappedAddress == derivativeWrappedAddress);
    }

    // validate
    // [X] when the vesting params are in the incorrect format
    //  [X] it returns false
    // [X] when the start timestamp is 0
    //  [X] it returns false
    // [X] when the expiry timestamp is 0
    //  [X] it returns false
    // [X] when the end timestamp is 0
    //  [X] it returns false
    // [X] when the start and expiry timestamps are the same
    //  [X] it returns false
    // [X] when the expiry and end timestamps are the same
    //  [X] it returns false
    // [X] when the start and end timestamps are the same
    //  [X] it returns false
    // [X] when the start timestamp is after the expiry timestamp
    //  [X] it returns false
    // [X] when the expiry timestamp is after the end timestamp
    //  [X] it returns false
    // [X] when the start timestamp is after the end timestamp
    //  [X] it returns false
    // [X] when the start timestamp is before the current timestamp
    //  [X] it returns false
    // [X] when the expiry timestamp is before the current timestamp
    //  [X] it returns false
    // [X] when the end timestamp is before the current timestamp
    //  [X] it returns false
    // [X] it returns true

    function test_validate_incorrectParams_reverts() public givenVestingParamsAreInvalid {
        // Expect revert
        vm.expectRevert();

        // Call
        linearVesting.validate(vestingParamsBytes);
    }

    function test_validate_startTimestampIsZero() public whenStartTimestampIsZero {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_expiryTimestampIsZero() public whenExpiryTimestampIsZero {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_endTimestampIsZero() public whenEndTimestampIsZero {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startAndExpiryTimestampsAreTheSame()
        public
        whenStartAndExpiryTimestampsAreTheSame
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_expiryAndEndTimestampsAreTheSame()
        public
        whenExpiryAndEndTimestampsAreTheSame
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startAndEndTimestampsAreTheSame()
        public
        whenStartAndEndTimestampsAreTheSame
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startTimestampIsAfterExpiryTimestamp()
        public
        whenStartTimestampIsAfterExpiryTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_expiryTimestampIsAfterEndTimestamp()
        public
        whenExpiryTimestampIsAfterEndTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startTimestampIsAfterEndTimestamp()
        public
        whenStartTimestampIsAfterEndTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startTimestampIsBeforeCurrentTimestamp()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_expiryTimestampIsBeforeCurrentTimestamp()
        public
        whenExpiryTimestampIsBeforeCurrentTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_endTimestampIsBeforeCurrentTimestamp()
        public
        whenEndTimestampIsBeforeCurrentTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate() public {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

        // Check values
        assertTrue(isValid);
    }

    // computeId
    // [ ] when the params are in the incorrect format
    //  [ ] it reverts
    // [ ] when the params are changed
    //  [ ] it returns a different id
    // [ ] it deterministically computes the token id

    // mint with params
    // [ ] when the vesting params are in the incorrect format
    //  [ ] it reverts
    // [ ] when the underlying token is 0
    //  [ ] it reverts
    // [ ] when the start timestamp is 0
    //  [ ] it reverts
    // [ ] when the expiry timestamp is 0
    //  [ ] it reverts
    // [ ] when the end timestamp is 0
    //  [ ] it reverts
    // [ ] when the start and expiry timestamps are the same
    //  [ ] it reverts
    // [ ] when the expiry and end timestamps are the same
    //  [ ] it reverts
    // [ ] when the start and end timestamps are the same
    //  [ ] it reverts
    // [ ] when the start timestamp is after the expiry timestamp
    //  [ ] it reverts
    // [ ] when the expiry timestamp is after the end timestamp
    //  [ ] it reverts
    // [ ] when the start timestamp is after the end timestamp
    //  [ ] it reverts
    // [ ] when the start timestamp is before the current timestamp
    //  [ ] it reverts
    // [ ] when the expiry timestamp is before the current timestamp
    //  [ ] it reverts
    // [ ] when the end timestamp is before the current timestamp
    //  [ ] it reverts
    // [ ] when the mint amount is 0
    //  [ ] it reverts
    // [ ] when the recipient is 0
    //  [ ] it reverts
    // [ ] given the caller has an insufficient balance of the underlying token
    //  [ ] it reverts
    // [ ] when wrapped is false
    //  [ ] given the token is not deployed
    //   [ ] it deploys the token and mints the derivative token
    //  [ ] it mints the derivative token
    // [ ] when wrapped is true
    //  [ ] given the wrapped token is not deployed
    //   [ ] it deploys the wrapped token and mints the wrapped token
    //  [ ] it mints the wrapped token
    // [ ] when the caller is not the parent
    //  [ ] it succeeds

    // mint with token id
    // [ ] when the token id does not exist
    //  [ ] it reverts
    // [ ] when the mint amount is 0
    //  [ ] it reverts
    // [ ] when the recipient is 0
    //  [ ] it reverts
    // [ ] given the caller has an insufficient balance of the underlying token
    //  [ ] it reverts
    // [ ] when wrapped is false
    //  [ ] it mints the derivative token
    // [ ] when wrapped is true
    //  [ ] given the wrapped token is not deployed
    //   [ ] it deploys the wrapped token and mints the wrapped token
    //  [ ] it mints the wrapped token
    // [ ] when the caller is not the parent
    //  [ ] it succeeds

    // redeem
    // [ ] when the token id does not exist
    //  [ ] it reverts
    // [ ] when the redeem amount is 0
    //  [ ] it reverts
    // [ ] given the redeemable amount is 0
    //  [ ] it reverts
    // [ ] when the redeem amount is more than the redeemable amount
    //  [ ] it reverts
    // [ ] when wrapped is true
    //  [ ] given the wrapped token is not deployed
    //   [ ] it reverts
    //  [ ] it burns the wrapped token and transfers the underlying
    // [ ] when wrapped is false
    //  [ ] it burns the derivative token and transfers the underlying

    // redeem max
    // [ ] when the token id does not exist
    //  [ ] it reverts
    // [ ] given the redeemable amount is 0
    //  [ ] it reverts
    // [ ] when wrapped is true
    //  [ ] given the wrapped token is not deployed
    //   [ ] it reverts
    //  [ ] it burns the wrapped token and transfers the underlying
    // [ ] when wrapped is false
    //  [ ] it burns the derivative token and transfers the underlying

    // redeemable
    // [ ] when the token id does not exist
    //  [ ] it reverts
    // [ ] given the block timestamp is before the start timestamp
    //  [ ] it returns 0
    // [ ] given the block timestamp is after the expiry timestamp
    //  [ ] it returns the full balance
    // [ ] given the block timestamp is after the end timestamp
    //  [ ] it returns 0
    // [ ] when wrapped is true
    //  [ ] given the wrapped token is not deployed
    //   [ ] it returns 0
    //  [ ] it returns the redeemable amount up to the wrapped token balance
    // [ ] when wrapped is false
    //  [ ] it returns the redeemable amount up to the derivative token balance
    // [ ] given tokens have been redeemed
    //  [ ] it returns the remaining redeemable amount
    // [ ] when the owner is not the caller
    //  [ ] it returns the owner's redeemable amount

    // reclaim
    // [ ] when the token id does not exist
    //  [ ] it reverts
    // [ ] when the caller is not the parent
    //  [ ] it reverts
    // [ ] when the token redemption period has not ended
    //  [ ] it reverts
    // [ ] it transfers the base token balance to the parent

    // wrap
    // [ ] when the token id does not exist
    //  [ ] it reverts
    // [ ] when the amount is 0
    //  [ ] it reverts
    // [ ] when the caller has insufficient balance of the derivative token
    //  [ ] it reverts
    // [ ] given the wrapped token has not been deployed
    //  [ ] it deploys the wrapped token, burns the derivative token and mints the wrapped token
    // [ ] given the wrapped token has been deployed
    //  [ ] it burns the derivative token and mints the wrapped token

    // unwrap
    // [ ] when the token id does not exist
    //  [ ] it reverts
    // [ ] when the amount is 0
    //  [ ] it reverts
    // [ ] given the wrapped token has not been deployed
    //  [ ] it reverts
    // [ ] when the caller has insufficient balance of the wrapped token
    //  [ ] it reverts
    // [ ] it burns the wrapped token and mints the derivative token

    // transfer
    // [ ] it reverts

    // transferFrom
    // [ ] it reverts

    // approve
    // [ ] it reverts

    // exerciseCost
    // [ ] it reverts

    // convertsTo
    // [ ] it reverts

    // transform
    // [ ] it reverts

    // exercise
    // [ ] it reverts
}
