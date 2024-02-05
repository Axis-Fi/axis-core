// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {StringHelper} from "test/lib/String.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";
import {Derivative} from "src/modules/Derivative.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";
import {SoulboundCloneERC20} from "src/modules/derivatives/SoulboundCloneERC20.sol";

contract LinearVestingTest is Test, Permit2User {
    using StringHelper for string;
    using FixedPointMathLib for uint256;

    address internal constant _owner = address(0x1);
    address internal constant _protocol = address(0x2);
    address internal constant _alice = address(0x3);

    MockERC20 internal underlyingToken;
    address internal underlyingTokenAddress;
    uint8 internal underlyingTokenDecimals = 18;

    AuctionHouse internal auctionHouse;
    LinearVesting internal linearVesting;

    LinearVesting.VestingParams internal vestingParams;
    bytes internal vestingParamsBytes;
    uint48 internal constant vestingStart = 1_704_882_344; // 2024-01-10
    uint48 internal constant vestingExpiry = 1_705_055_144; // 2024-01-12
    uint48 internal constant vestingDuration = vestingExpiry - vestingStart;

    uint256 internal constant AMOUNT = 1e18;

    uint256 internal constant VESTING_DATA_LEN = 96;

    uint256 internal derivativeTokenId;
    address internal derivativeWrappedAddress;
    string internal wrappedDerivativeTokenName;
    string internal wrappedDerivativeTokenSymbol;
    uint256 internal wrappedDerivativeTokenNameLength;
    uint256 internal wrappedDerivativeTokenSymbolLength;

    function setUp() public {
        // Wrap to reasonable timestamp
        vm.warp(1_000_000);

        underlyingToken = new MockERC20("Underlying", "UNDERLYING", underlyingTokenDecimals);
        underlyingTokenAddress = address(underlyingToken);

        auctionHouse = new AuctionHouse(_protocol, _PERMIT2_ADDRESS);
        linearVesting = new LinearVesting(address(auctionHouse));
        auctionHouse.installModule(linearVesting);

        vestingParams = LinearVesting.VestingParams({start: vestingStart, expiry: vestingExpiry});
        vestingParamsBytes = abi.encode(vestingParams);

        wrappedDerivativeTokenName = "Underlying 2024-01-12";
        wrappedDerivativeTokenSymbol = "UNDERLYING 2024-01-12";
        wrappedDerivativeTokenNameLength = bytes(wrappedDerivativeTokenName).length;
        wrappedDerivativeTokenSymbolLength = bytes(wrappedDerivativeTokenSymbol).length;
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

    modifier whenStartAndExpiryTimestampsAreTheSame() {
        vestingParams.expiry = vestingParams.start;
        vestingParamsBytes = abi.encode(vestingParams);
        _;
    }

    modifier whenStartTimestampIsAfterExpiryTimestamp() {
        vestingParams.start = vestingParams.expiry + 1;
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

    modifier whenVestingParamsAreChanged() {
        vestingParams.expiry = 1_705_227_944; // 2024-01-14
        vestingParamsBytes = abi.encode(vestingParams);

        wrappedDerivativeTokenName = "Underlying 2024-01-14";
        wrappedDerivativeTokenSymbol = "UNDERLYING 2024-01-14";
        wrappedDerivativeTokenNameLength = bytes(wrappedDerivativeTokenName).length;
        wrappedDerivativeTokenSymbolLength = bytes(wrappedDerivativeTokenSymbol).length;
        _;
    }

    modifier whenUnderlyingTokenIsChanged() {
        underlyingTokenDecimals = 17;
        underlyingToken = new MockERC20("Underlying2", "UNDERLYING2", underlyingTokenDecimals);
        underlyingTokenAddress = address(underlyingToken);

        wrappedDerivativeTokenName = "Underlying2 2024-01-12";
        wrappedDerivativeTokenSymbol = "UNDERLYING2 2024-01-12";
        wrappedDerivativeTokenNameLength = bytes(wrappedDerivativeTokenName).length;
        wrappedDerivativeTokenSymbolLength = bytes(wrappedDerivativeTokenSymbol).length;
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

        vm.prank(address(auctionHouse));
        underlyingToken.approve(address(linearVesting), balance_);
        _;
    }

    modifier givenCallerHasUnderlyingTokenBalance(address caller_, uint256 balance_) {
        underlyingToken.mint(caller_, balance_);

        vm.prank(address(caller_));
        underlyingToken.approve(address(linearVesting), balance_);
        _;
    }

    modifier givenBeforeVestingStart() {
        vm.warp(vestingStart - 1);
        _;
    }

    modifier givenAfterVestingExpiry() {
        vm.warp(vestingExpiry + 1);
        _;
    }

    function _mintDerivativeTokens(address recipient_, uint256 amount_) internal {
        // Mint underlying tokens for transfer
        underlyingToken.mint(address(auctionHouse), amount_);

        // Approve spending of underlying tokens (which is done in the AuctionHouse)
        vm.prank(address(auctionHouse));
        underlyingToken.approve(address(linearVesting), amount_);

        // Mint derivative tokens
        vm.prank(address(auctionHouse));
        linearVesting.mint(recipient_, underlyingTokenAddress, vestingParamsBytes, amount_, false);
    }

    modifier givenAliceHasDerivativeTokens(uint256 amount_) {
        _mintDerivativeTokens(_alice, amount_);
        _;
    }

    function _mintWrappedDerivativeTokens(address recipient_, uint256 amount_) internal {
        // Mint underlying tokens for transfer
        underlyingToken.mint(address(auctionHouse), amount_);

        // Approve spending of underlying tokens (which is done in the AuctionHouse)
        vm.prank(address(auctionHouse));
        underlyingToken.approve(address(linearVesting), amount_);

        // Mint wrapped derivative tokens
        vm.prank(address(auctionHouse));
        linearVesting.mint(recipient_, underlyingTokenAddress, vestingParamsBytes, amount_, true);
    }

    modifier givenAliceHasWrappedDerivativeTokens(uint256 amount_) {
        _mintWrappedDerivativeTokens(_alice, amount_);
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
    // [X] when the start and expiry timestamps are the same
    //  [X] it reverts
    // [X] when the start timestamp is after the expiry timestamp
    //  [X] it reverts
    // [X] when the start timestamp is before the current timestamp
    //  [X] it succeeds
    // [X] when the expiry timestamp is before the current timestamp
    //  [X] it reverts
    // [X] given the token is already deployed
    //  [X] given the wrapped token is already deployed
    //   [X] it returns the same token id and wrapped token address
    //  [X] it returns the token id and deploys the wrapped token
    // [X] given the token is not already deployed
    //  [X] it deploys the token and wrapped token
    // [X] when the caller is not the parent
    //  [X] it succeeds
    // [X] when the parameters change
    //  [X] it returns a different token id

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

    function test_deploy_startTimestampIsBeforeCurrentTimestamp()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress != address(0), "wrappedAddress mismatch");
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

    function test_deploy_wrapped_derivativeDeployed_wrappedDerivativeDeployed()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertEq(wrappedAddress, derivativeWrappedAddress);

        // Check token metadata
        Derivative.Token memory tokenMetadata = linearVesting.getTokenMetadata(tokenId);
        assertEq(tokenMetadata.exists, true);
        assertEq(tokenMetadata.wrapped, wrappedAddress);
        assertEq(tokenMetadata.underlyingToken, underlyingTokenAddress);
        assertEq(tokenMetadata.data.length, VESTING_DATA_LEN);

        // Check implementation data
        LinearVesting.VestingData memory vestingData =
            abi.decode(tokenMetadata.data, (LinearVesting.VestingData));
        assertEq(vestingData.start, vestingStart);
        assertEq(vestingData.expiry, vestingExpiry);
        assertEq(address(vestingData.baseToken), underlyingTokenAddress);
    }

    function test_deploy_wrapped_derivativeDeployed_wrappedDerivativeNotDeployed()
        public
        givenDerivativeIsDeployed
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertTrue(wrappedAddress != address(0));

        // Check token metadata
        Derivative.Token memory tokenMetadata = linearVesting.getTokenMetadata(tokenId);
        assertEq(tokenMetadata.exists, true);
        assertEq(tokenMetadata.wrapped, wrappedAddress);
        assertEq(tokenMetadata.underlyingToken, underlyingTokenAddress);
        assertEq(tokenMetadata.data.length, VESTING_DATA_LEN);

        // Check implementation data
        LinearVesting.VestingData memory vestingData =
            abi.decode(tokenMetadata.data, (LinearVesting.VestingData));
        assertEq(vestingData.start, vestingStart);
        assertEq(vestingData.expiry, vestingExpiry);
        assertEq(address(vestingData.baseToken), underlyingTokenAddress);
    }

    function test_deploy_wrapped() public {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertTrue(tokenId > 0);
        assertTrue(wrappedAddress != address(0));

        // Check wrapped token
        SoulboundCloneERC20 wrappedDerivative = SoulboundCloneERC20(wrappedAddress);
        assertEq(
            wrappedDerivative.name().trim(0, wrappedDerivativeTokenNameLength),
            wrappedDerivativeTokenName
        );
        assertEq(
            wrappedDerivative.symbol().trim(0, wrappedDerivativeTokenSymbolLength),
            wrappedDerivativeTokenSymbol
        );
        assertEq(wrappedDerivative.decimals(), 18);
        assertEq(address(wrappedDerivative.underlying()), underlyingTokenAddress);
        assertEq(wrappedDerivative.expiry(), vestingExpiry);
        assertEq(wrappedDerivative.owner(), address(linearVesting));

        // Check token metadata
        Derivative.Token memory tokenMetadata = linearVesting.getTokenMetadata(tokenId);
        assertEq(tokenMetadata.exists, true);
        assertEq(tokenMetadata.wrapped, wrappedAddress);
        assertEq(tokenMetadata.underlyingToken, underlyingTokenAddress);
        assertEq(tokenMetadata.data.length, VESTING_DATA_LEN);

        // Check implementation data
        LinearVesting.VestingData memory vestingData =
            abi.decode(tokenMetadata.data, (LinearVesting.VestingData));
        assertEq(vestingData.start, vestingStart);
        assertEq(vestingData.expiry, vestingExpiry);
        assertEq(address(vestingData.baseToken), underlyingTokenAddress);
    }

    function test_deploy_notWrapped() public {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, false);

        // Check values
        assertTrue(tokenId > 0);
        assertTrue(wrappedAddress == address(0));

        // Check token metadata
        Derivative.Token memory tokenMetadata = linearVesting.getTokenMetadata(tokenId);
        assertEq(tokenMetadata.exists, true);
        assertEq(tokenMetadata.wrapped, address(0));
        assertEq(tokenMetadata.underlyingToken, underlyingTokenAddress);
        assertEq(tokenMetadata.data.length, VESTING_DATA_LEN);

        // Check implementation data
        LinearVesting.VestingData memory vestingData =
            abi.decode(tokenMetadata.data, (LinearVesting.VestingData));
        assertEq(vestingData.start, vestingStart);
        assertEq(vestingData.expiry, vestingExpiry);
        assertEq(address(vestingData.baseToken), underlyingTokenAddress);
    }

    function test_deploy_notParent() public {
        // Call
        vm.prank(_alice);
        (uint256 tokenId, address wrappedAddress) =
            linearVesting.deploy(underlyingTokenAddress, vestingParamsBytes, true);

        // Check values
        assertTrue(tokenId > 0);
        assertTrue(wrappedAddress != address(0));

        // Check wrapped token
        SoulboundCloneERC20 wrappedDerivative = SoulboundCloneERC20(wrappedAddress);
        assertEq(
            wrappedDerivative.name().trim(0, wrappedDerivativeTokenNameLength),
            wrappedDerivativeTokenName
        );
        assertEq(
            wrappedDerivative.symbol().trim(0, wrappedDerivativeTokenSymbolLength),
            wrappedDerivativeTokenSymbol
        );
        assertEq(wrappedDerivative.decimals(), 18);
        assertEq(address(wrappedDerivative.underlying()), underlyingTokenAddress);
        assertEq(wrappedDerivative.expiry(), vestingParams.expiry);
        assertEq(wrappedDerivative.owner(), address(linearVesting));
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

        // Check wrapped token
        SoulboundCloneERC20 wrappedDerivative = SoulboundCloneERC20(wrappedAddress);
        assertEq(
            wrappedDerivative.name().trim(0, wrappedDerivativeTokenNameLength),
            wrappedDerivativeTokenName
        );
        assertEq(
            wrappedDerivative.symbol().trim(0, wrappedDerivativeTokenSymbolLength),
            wrappedDerivativeTokenSymbol
        );
        assertEq(wrappedDerivative.decimals(), 18);
        assertEq(address(wrappedDerivative.underlying()), underlyingTokenAddress);
        assertEq(wrappedDerivative.expiry(), vestingParams.expiry);
        assertEq(wrappedDerivative.owner(), address(linearVesting));
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

        // Check wrapped token
        SoulboundCloneERC20 wrappedDerivative = SoulboundCloneERC20(wrappedAddress);
        assertEq(
            wrappedDerivative.name().trim(0, wrappedDerivativeTokenNameLength),
            wrappedDerivativeTokenName
        );
        assertEq(
            wrappedDerivative.symbol().trim(0, wrappedDerivativeTokenSymbolLength),
            wrappedDerivativeTokenSymbol
        );
        assertEq(wrappedDerivative.decimals(), 17);
        assertEq(address(wrappedDerivative.underlying()), underlyingTokenAddress);
        assertEq(wrappedDerivative.expiry(), vestingParams.expiry);
        assertEq(wrappedDerivative.owner(), address(linearVesting));
    }

    // validate
    // [X] when the vesting params are in the incorrect format
    //  [X] it returns false
    // [X] when the start timestamp is 0
    //  [X] it returns false
    // [X] when the expiry timestamp is 0
    //  [X] it returns false
    // [X] when the start and expiry timestamps are the same
    //  [X] it returns false
    // [X] when the start timestamp is after the expiry timestamp
    //  [X] it returns false
    // [X] when the start timestamp is before the current timestamp
    //  [X] it returns false
    // [X] when the expiry timestamp is before the current timestamp
    //  [X] it returns false
    // [X] it returns true

    function test_validate_incorrectParams_reverts() public givenVestingParamsAreInvalid {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.validate(underlyingTokenAddress, vestingParamsBytes);
    }

    function test_validate_startTimestampIsZero() public whenStartTimestampIsZero {
        // Call
        bool isValid = linearVesting.validate(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_expiryTimestampIsZero() public whenExpiryTimestampIsZero {
        // Call
        bool isValid = linearVesting.validate(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startAndExpiryTimestampsAreTheSame()
        public
        whenStartAndExpiryTimestampsAreTheSame
    {
        // Call
        bool isValid = linearVesting.validate(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startTimestampIsAfterExpiryTimestamp()
        public
        whenStartTimestampIsAfterExpiryTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startTimestampIsBeforeCurrentTimestamp()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertTrue(isValid);
    }

    function test_validate_expiryTimestampIsBeforeCurrentTimestamp()
        public
        whenExpiryTimestampIsBeforeCurrentTimestamp
    {
        // Call
        bool isValid = linearVesting.validate(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate() public {
        // Call
        bool isValid = linearVesting.validate(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertTrue(isValid);
    }

    // computeId
    // [X] when the params are in the incorrect format
    //  [X] it reverts
    // [X] when the params are changed
    //  [X] it returns a different id
    // [X] it deterministically computes the token id

    function test_computeId_incorrectParams_reverts() public givenVestingParamsAreInvalid {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.computeId(underlyingTokenAddress, vestingParamsBytes);
    }

    function test_computeId_paramsChanged()
        public
        givenDerivativeIsDeployed
        whenVestingParamsAreChanged
    {
        // Call
        uint256 tokenId = linearVesting.computeId(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertFalse(tokenId == derivativeTokenId);
    }

    function test_computeId() public givenDerivativeIsDeployed {
        // Call
        uint256 tokenId = linearVesting.computeId(underlyingTokenAddress, vestingParamsBytes);

        // Check values
        assertEq(tokenId, derivativeTokenId);
    }

    // mint with params
    // [X] when the vesting params are in the incorrect format
    //  [X] it reverts
    // [X] when the underlying token is 0
    //  [X] it reverts
    // [X] when the start timestamp is 0
    //  [X] it reverts
    // [X] when the expiry timestamp is 0
    //  [X] it reverts
    // [X] when the start and expiry timestamps are the same
    //  [X] it reverts
    // [X] when the start timestamp is after the expiry timestamp
    //  [X] it reverts
    // [X] when the start timestamp is before the current timestamp
    //  [X] it reverts
    // [X] when the expiry timestamp is before the current timestamp
    //  [X] it reverts
    // [X] when the mint amount is 0
    //  [X] it reverts
    // [X] when the recipient is 0
    //  [X] it succeeds
    // [X] given the caller has an insufficient balance of the underlying token
    //  [X] it reverts
    // [X] when wrapped is false
    //  [X] given the token is not deployed
    //   [X] it deploys the token and mints the derivative token
    //  [X] it mints the derivative token
    // [X] when wrapped is true
    //  [X] given the wrapped token is not deployed
    //   [X] it deploys the wrapped token and mints the wrapped token
    //  [X] it mints the wrapped token
    // [X] when the caller is not the parent
    //  [X] it succeeds

    function test_mint_params_incorrectParams_reverts() public givenVestingParamsAreInvalid {
        // Expect revert
        vm.expectRevert();

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_underlyingTokenIsZero_reverts() public whenUnderlyingTokenIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_startTimestampIsZero_reverts() public whenStartTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_expiryTimestampIsZero_reverts() public whenExpiryTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_startAndExpiryTimestampsAreTheSame_reverts()
        public
        whenStartAndExpiryTimestampsAreTheSame
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_startTimestampIsAfterExpiryTimestamp_reverts()
        public
        whenStartTimestampIsAfterExpiryTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_startTimestampIsBeforeCurrentTimestamp()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
        givenParentHasUnderlyingTokenBalance(AMOUNT)
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, AMOUNT, "amountCreated mismatch");
        assertEq(linearVesting.balanceOf(_alice, tokenId), AMOUNT, "balanceOf mismatch");
    }

    function test_mint_params_expiryTimestampIsBeforeCurrentTimestamp_reverts()
        public
        whenExpiryTimestampIsBeforeCurrentTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_afterExpiry_reverts()
        public
        givenDerivativeIsDeployed
        givenAfterVestingExpiry
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_mintAmountIsZero_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, 0, false);
    }

    function test_mint_params_recipientIsZero()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId,,) = linearVesting.mint(
            address(0), underlyingTokenAddress, vestingParamsBytes, AMOUNT, false
        );

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertEq(linearVesting.balanceOf(address(0), tokenId), AMOUNT, "balanceOf mismatch");
    }

    function test_mint_params_insufficentBalance_reverts() public {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    function test_mint_params_notWrapped_tokenNotDeployed()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, AMOUNT, "amountCreated mismatch");
        assertEq(linearVesting.balanceOf(_alice, tokenId), AMOUNT, "balanceOf mismatch");
    }

    function test_mint_params_notWrapped_tokenDeployed()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, AMOUNT, "amountCreated mismatch");
        assertEq(linearVesting.balanceOf(_alice, tokenId), AMOUNT, "balanceOf mismatch");
    }

    function test_mint_params_wrapped_wrappedTokenIsNotDeployed()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, true);

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress != address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, AMOUNT, "amountCreated mismatch");
        assertEq(linearVesting.balanceOf(_alice, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_alice), AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_params_wrapped_wrappedTokenIsDeployed()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, true);

        // Check values
        assertEq(tokenId, derivativeTokenId, "tokenId mismatch");
        assertEq(wrappedAddress, derivativeWrappedAddress, "wrappedAddress mismatch");
        assertEq(amountCreated, AMOUNT, "amountCreated mismatch");
        assertEq(linearVesting.balanceOf(_alice, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_alice), AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_params_notParent()
        public
        givenCallerHasUnderlyingTokenBalance(_alice, AMOUNT)
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(_alice);
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, true);

        // Check values
        assertEq(tokenId, derivativeTokenId, "tokenId mismatch");
        assertEq(wrappedAddress, derivativeWrappedAddress, "wrappedAddress mismatch");
        assertEq(amountCreated, AMOUNT, "amountCreated mismatch");
        assertEq(linearVesting.balanceOf(_alice, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_alice), AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_params_notParent_insufficientBalance_reverts()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call
        vm.prank(_alice);
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
    }

    // mint with token id
    // [X] when the token id does not exist
    //  [X] it reverts
    // [X] when the mint amount is 0
    //  [X] it reverts
    // [X] when the recipient is 0
    //  [X] it succeeds
    // [X] given the caller has an insufficient balance of the underlying token
    //  [X] it reverts
    // [X] when wrapped is false
    //  [X] it mints the derivative token
    // [X] when wrapped is true
    //  [X] given the wrapped token is not deployed
    //   [X] it deploys the wrapped token and mints the wrapped token
    //  [X] it mints the wrapped token
    // [X] when the caller is not the parent
    //  [X] it succeeds

    function test_mint_tokenId_whenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, derivativeTokenId, AMOUNT, false);
    }

    function test_mint_tokenId_afterExpiry_reverts()
        public
        givenDerivativeIsDeployed
        givenAfterVestingExpiry
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, derivativeTokenId, AMOUNT, false);
    }

    function test_mint_tokenId_whenMintAmountIsZero_reverts() public givenDerivativeIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, derivativeTokenId, 0, false);
    }

    function test_mint_tokenId_whenRecipientIsZero()
        public
        givenDerivativeIsDeployed
        givenParentHasUnderlyingTokenBalance(AMOUNT)
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId,,) = linearVesting.mint(address(0), derivativeTokenId, AMOUNT, false);

        // Check values
        assertEq(linearVesting.balanceOf(address(0), tokenId), AMOUNT);
    }

    function test_mint_tokenId_insufficentBalance_reverts() public givenDerivativeIsDeployed {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, derivativeTokenId, AMOUNT, false);
    }

    function test_mint_tokenId_notWrapped()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, derivativeTokenId, AMOUNT, false);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertTrue(wrappedAddress == address(0));
        assertEq(amountCreated, AMOUNT);
        assertEq(linearVesting.balanceOf(_alice, tokenId), AMOUNT, "balanceOf mismatch");
    }

    function test_mint_tokenId_wrapped_wrappedTokenIsNotDeployed()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, derivativeTokenId, AMOUNT, true);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertTrue(wrappedAddress != address(0));
        assertEq(amountCreated, AMOUNT);
        assertEq(linearVesting.balanceOf(_alice, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_alice), AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_tokenId_wrapped_wrappedTokenIsDeployed()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(address(auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, derivativeTokenId, AMOUNT, true);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertEq(wrappedAddress, derivativeWrappedAddress);
        assertEq(amountCreated, AMOUNT);
        assertEq(linearVesting.balanceOf(_alice, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_alice), AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_tokenId_notParent()
        public
        givenCallerHasUnderlyingTokenBalance(_alice, AMOUNT)
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(_alice);
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            linearVesting.mint(_alice, derivativeTokenId, AMOUNT, true);

        // Check values
        assertEq(tokenId, derivativeTokenId);
        assertEq(wrappedAddress, derivativeWrappedAddress);
        assertEq(amountCreated, AMOUNT);
        assertEq(linearVesting.balanceOf(_alice, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_alice), AMOUNT, "balanceOf mismatch"
        );
    }

    // redeem
    // [X] when the token id does not exist
    //  [X] it reverts
    // [X] when the redeem amount is 0
    //  [X] it reverts
    // [X] given the redeemable amount is 0
    //  [X] it reverts
    // [X] when the redeem amount is more than the redeemable amount
    //  [X] it reverts
    // [X] when wrapped is true
    //  [X] given the wrapped token is not deployed
    //   [X] it reverts
    //  [X] it burns the wrapped token and transfers the underlying
    // [X] when wrapped is false
    //  [X] it burns the derivative token and transfers the underlying

    function test_redeem_givenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, AMOUNT, false);
    }

    function test_redeem_givenRedeemAmountIsZero_reverts() public givenDerivativeIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, 0, false);
    }

    function test_redeem_givenAmountGreaterThanRedeemable_reverts(uint48 elapsed_)
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        // Warp to mid-way, so not all tokens are vested
        uint48 elapsed = uint48(bound(elapsed_, 1, vestingDuration - 1));
        vm.warp(vestingStart + elapsed);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, AMOUNT, false);
    }

    function test_redeem_insufficientBalance_reverts()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.redeem(derivativeTokenId, AMOUNT, false);
    }

    function test_redeem_wrapped_givenWrappedTokenNotDeployed()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, AMOUNT, true);
    }

    function test_redeem_wrapped(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, amount, true);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), AMOUNT - amount);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), amount);
    }

    function test_redeem_notWrapped(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, amount, false);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), AMOUNT - amount);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), 0);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), amount);
    }

    // redeem max
    // [X] when the token id does not exist
    //  [X] it reverts
    // [X] given the redeemable amount is 0
    //  [X] it reverts
    // [X] when wrapped is true
    //  [X] given the wrapped token is not deployed
    //   [X] it reverts
    //  [X] it burns the wrapped token and transfers the underlying
    // [X] when wrapped is false
    //  [X] it burns the derivative token and transfers the underlying

    function test_redeemMax_givenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId, false);
    }

    function test_redeemMax_givenRedeemableAmountIsZero_reverts()
        public
        givenDerivativeIsDeployed
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId, false);
    }

    function test_redeemMax_wrapped_givenWrappedTokenNotDeployed()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId, true);
    }

    function test_redeemMax_wrapped(uint48 elapsed_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        // Warp during vesting
        uint48 elapsed = uint48(bound(elapsed_, 1, vestingDuration - 1));
        vm.warp(vestingStart + elapsed);

        uint256 redeemableAmount = elapsed * AMOUNT / vestingDuration;

        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId, true);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0);
        assertEq(
            SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice),
            AMOUNT - redeemableAmount
        );
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), redeemableAmount);
    }

    function test_redeemMax_wrapped_givenVestingExpiry()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId, true);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), 0);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), AMOUNT);
    }

    function test_redeemMax_notWrapped(uint48 elapsed_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        // Warp during vesting
        uint48 elapsed = uint48(bound(elapsed_, 1, vestingDuration - 1));
        vm.warp(vestingStart + elapsed);

        uint256 redeemableAmount = elapsed * AMOUNT / vestingDuration;

        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId, false);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), AMOUNT - redeemableAmount);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), 0);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), redeemableAmount);
    }

    function test_redeemMax_notWrapped_givenVestingExpiry()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId, false);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), 0);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), AMOUNT);
    }

    // redeemable
    // [X] when the token id does not exist
    //  [X] it reverts
    // [X] given the block timestamp is before the start timestamp
    //  [X] it returns 0
    // [X] given the block timestamp is after the expiry timestamp
    //  [X] it returns the full balance
    // [X] when wrapped is true
    //  [X] given the wrapped token is not deployed
    //   [X] it returns 0
    //  [X] it returns the redeemable amount up to the wrapped token balance
    // [X] when wrapped is false
    //  [X] it returns the redeemable amount up to the derivative token balance
    // [X] given tokens have been redeemed
    //  [X] it returns the remaining redeemable amount
    // [X] when the derivative is minted after start timestamp
    //  [X] given tokens have been redeemed
    //   [X] it returns the remaining redeemable amount
    //  [X] it returns the expected balance
    // [X] given wrapped derivative tokens have been redeemed
    //  [X] given wrapped derivative tokens have been unwrapped
    //   [X] it returns the remaining wrapped and unwrapped redeemable amount
    // [X] given unwrapped derivative tokens have been redeemed
    //  [X] given unwrapped derivative tokens have been wrapped
    //   [X] it returns the remaining wrapped and unwrapped redeemable amount

    function test_redeemable_givenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.redeemable(_alice, derivativeTokenId, false);
    }

    function test_redeemable_givenBlockTimestampIsBeforeStartTimestamp_returnsZero()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenBeforeVestingStart
    {
        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, false);

        // Check values
        assertEq(redeemableAmount, 0);
    }

    function test_redeemable_givenBlockTimestampIsAfterExpiryTimestamp_returnsFullBalance()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, false);

        // Check values
        assertEq(redeemableAmount, AMOUNT);
    }

    function test_redeemable_wrapped_givenWrappedTokenNotDeployed()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, true);

        // Check values
        assertEq(redeemableAmount, 0);
    }

    function test_redeemable_wrapped(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, amount);

        // Warp to expiry
        vm.warp(vestingParams.expiry + 1);

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, true);

        // Check values
        assertEq(redeemableAmount, amount); // Does not include unwrapped derivative balance
    }

    function test_redeemable_wrapped_givenBeforeExpiry(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, amount);

        // Warp to before expiry
        uint48 elapsed = 100_000;
        vm.warp(vestingParams.start + elapsed);

        uint256 expectedRedeemable = elapsed * amount / vestingDuration;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, true);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable); // Does not include unwrapped derivative balance
    }

    function test_redeemable_notWrapped(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Mint derivative tokens
        _mintDerivativeTokens(_alice, amount);

        // Warp to expiry
        vm.warp(vestingParams.expiry + 1);

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, false);

        // Check values
        assertEq(redeemableAmount, amount); // Does not include wwrapped derivative balance
    }

    function test_redeemable_notWrapped_givenBeforeExpiry(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Mint derivative tokens
        _mintDerivativeTokens(_alice, amount);

        // Warp to before expiry
        uint48 elapsed = 100_000;
        vm.warp(vestingParams.start + elapsed);

        uint256 expectedRedeemable = elapsed * amount / vestingDuration;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, false);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable); // Does not include wrapped derivative balance
    }

    function test_redeemable_notWrapped_givenRedemption(
        uint256 wrappedAmount_,
        uint256 unwrappedAmount_,
        uint256 wrappedRedeemPercentage_,
        uint256 unwrappedRedeemPercentage_
    ) public givenWrappedDerivativeIsDeployed {
        uint256 wrappedAmount = bound(wrappedAmount_, 1, AMOUNT);
        uint256 unwrappedAmount = bound(unwrappedAmount_, 1, AMOUNT);
        uint256 wrappedRedeemPercentage = bound(wrappedRedeemPercentage_, 1, 100);
        uint256 unwrappedRedeemPercentage = bound(unwrappedRedeemPercentage_, 1, 100);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, wrappedAmount);

        // Mint derivative tokens
        _mintDerivativeTokens(_alice, unwrappedAmount);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        // Redeem wrapped tokens
        uint256 redeemableWrapped = elapsed * wrappedAmount / vestingDuration;
        uint256 redeemAmountWrapped = redeemableWrapped * wrappedRedeemPercentage / 100;
        if (redeemAmountWrapped > 0) {
            vm.prank(_alice);
            linearVesting.redeem(derivativeTokenId, redeemAmountWrapped, true);
        }

        // Redeem unwrapped tokens
        uint256 redeemableUnwrapped = elapsed * unwrappedAmount / vestingDuration;
        uint256 redeemAmountUnwrapped = redeemableUnwrapped * unwrappedRedeemPercentage / 100;
        if (redeemAmountUnwrapped > 0) {
            vm.prank(_alice);
            linearVesting.redeem(derivativeTokenId, redeemAmountUnwrapped, false);
        }

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, false);

        // Check values
        assertEq(
            redeemableAmount, redeemableUnwrapped - redeemAmountUnwrapped, "redeemable mismatch"
        ); // Not affected by the other balance
    }

    function test_redeemable_wrapped_givenRedemption(
        uint256 wrappedAmount_,
        uint256 unwrappedAmount_,
        uint256 wrappedRedeemPercentage_,
        uint256 unwrappedRedeemPercentage_
    ) public givenWrappedDerivativeIsDeployed {
        uint256 wrappedAmount = bound(wrappedAmount_, 1, AMOUNT);
        uint256 unwrappedAmount = bound(unwrappedAmount_, 1, AMOUNT);
        uint256 wrappedRedeemPercentage = bound(wrappedRedeemPercentage_, 1, 100);
        uint256 unwrappedRedeemPercentage = bound(unwrappedRedeemPercentage_, 1, 100);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, wrappedAmount);

        // Mint derivative tokens
        _mintDerivativeTokens(_alice, unwrappedAmount);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        // Redeem wrapped tokens
        uint256 redeemableWrapped = elapsed * wrappedAmount / vestingDuration;
        uint256 redeemAmountWrapped = redeemableWrapped * wrappedRedeemPercentage / 100;
        if (redeemAmountWrapped > 0) {
            vm.prank(_alice);
            linearVesting.redeem(derivativeTokenId, redeemAmountWrapped, true);
        }

        // Redeem unwrapped tokens
        uint256 redeemableUnwrapped = elapsed * unwrappedAmount / vestingDuration;
        uint256 redeemAmountUnwrapped = redeemableUnwrapped * unwrappedRedeemPercentage / 100;
        if (redeemAmountUnwrapped > 0) {
            vm.prank(_alice);
            linearVesting.redeem(derivativeTokenId, redeemAmountUnwrapped, false);
        }

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, true);

        // Check values
        assertEq(redeemableAmount, redeemableWrapped - redeemAmountWrapped, "redeemable mismatch"); // Not affected by the other balance
    }

    function test_redeemable_notWrapped_redemptions() public givenWrappedDerivativeIsDeployed {
        // Mint derivative tokens
        _mintDerivativeTokens(_alice, AMOUNT);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        // Calculate the vested amount
        uint256 vestedAmount = elapsed * AMOUNT / vestingDuration;
        uint256 claimedAmount = 0;
        uint256 redeemableAmount = vestedAmount - claimedAmount;

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            redeemableAmount,
            "1: redeemable mismatch, unwrapped"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            0,
            "1: redeemable mismatch, wrapped"
        );

        // Redeem half the tokens
        uint256 redeemAmount = redeemableAmount / 2;
        claimedAmount += redeemAmount;
        redeemableAmount = vestedAmount - claimedAmount;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount, false);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            redeemableAmount,
            "2: redeemable mismatch, unwrapped"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            0,
            "2: redeemable mismatch, wrapped"
        );

        // Redeem the remaining tokens
        redeemAmount = redeemableAmount;
        claimedAmount += redeemAmount;
        redeemableAmount = 0;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount, false);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            redeemableAmount,
            "3: redeemable mismatch, unwrapped"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            0,
            "3: redeemable mismatch, wrapped"
        );

        // Check that the claimed amount is the same as the vested amount
        assertEq(claimedAmount, vestedAmount, "claimedAmount mismatch");

        // Warp to another time
        elapsed = 60_000;
        vm.warp(vestingParams.start + elapsed);

        // Calculate the vested amount
        vestedAmount = elapsed * AMOUNT / vestingDuration;
        redeemableAmount = vestedAmount - claimedAmount;

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            redeemableAmount,
            "4: redeemable mismatch, unwrapped"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            0,
            "4: redeemable mismatch, wrapped"
        );

        // Redeem half the tokens
        redeemAmount = redeemableAmount / 2;
        claimedAmount += redeemAmount;
        redeemableAmount = vestedAmount - claimedAmount;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount, false);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            redeemableAmount,
            "5: redeemable mismatch"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            0,
            "5: redeemable mismatch, wrapped"
        );

        // Redeem the remaining tokens
        redeemAmount = redeemableAmount;
        claimedAmount += redeemAmount;
        redeemableAmount = 0;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount, false);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            redeemableAmount,
            "6: redeemable mismatch"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            0,
            "6: redeemable mismatch, wrapped"
        );

        // Check that the claimed amount is the same as the vested amount
        assertEq(claimedAmount, vestedAmount, "claimedAmount mismatch");
    }

    function test_redeemable_wrapped_redemptions() public givenWrappedDerivativeIsDeployed {
        // Mint derivative tokens
        _mintWrappedDerivativeTokens(_alice, AMOUNT);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        // Calculate the vested amount
        uint256 vestedAmount = elapsed * AMOUNT / vestingDuration;
        uint256 claimedAmount = 0;
        uint256 redeemableAmount = vestedAmount - claimedAmount;

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            0,
            "1: redeemable mismatch, unwrapped"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            redeemableAmount,
            "1: redeemable mismatch, wrapped"
        );

        // Redeem half the tokens
        uint256 redeemAmount = redeemableAmount / 2;
        claimedAmount += redeemAmount;
        redeemableAmount = vestedAmount - claimedAmount;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount, true);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            0,
            "2: redeemable mismatch, unwrapped"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            redeemableAmount,
            "2: redeemable mismatch, wrapped"
        );

        // Redeem the remaining tokens
        redeemAmount = redeemableAmount;
        claimedAmount += redeemAmount;
        redeemableAmount = 0;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount, true);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            0,
            "3: redeemable mismatch, unwrapped"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            redeemableAmount,
            "3: redeemable mismatch, wrapped"
        );

        // Warp to another time
        elapsed = 60_000;
        vm.warp(vestingParams.start + elapsed);

        // Calculate the vested amount
        vestedAmount = elapsed * AMOUNT / vestingDuration;
        redeemableAmount = vestedAmount - claimedAmount;

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false),
            0,
            "4: redeemable mismatch, unwrapped"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            redeemableAmount,
            "4: redeemable mismatch, wrapped"
        );

        // Redeem half the tokens
        redeemAmount = redeemableAmount / 2;
        claimedAmount += redeemAmount;
        redeemableAmount = vestedAmount - claimedAmount;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount, true);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false), 0, "5: redeemable mismatch"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            redeemableAmount,
            "5: redeemable mismatch, wrapped"
        );

        // Redeem the remaining tokens
        redeemAmount = redeemableAmount;
        claimedAmount += redeemAmount;
        redeemableAmount = 0;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount, true);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, false), 0, "6: redeemable mismatch"
        );
        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId, true),
            redeemableAmount,
            "6: redeemable mismatch, wrapped"
        );
    }

    function test_redeemable_notWrapped_givenTokensMintedAfterDeployment()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        // Mint tokens
        _mintDerivativeTokens(_alice, AMOUNT);

        uint256 expectedRedeemable = elapsed * AMOUNT / vestingDuration;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, false);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable); // Does not include wrapped derivative balance
    }

    function test_redeemable_wrapped_givenTokensMintedAfterDeployment()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        // Mint tokens
        _mintWrappedDerivativeTokens(_alice, AMOUNT);

        uint256 expectedRedeemable = elapsed * AMOUNT / vestingDuration;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, true);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable); // Does not include unwrapped derivative balance
    }

    function test_redeemable_notWrapped_givenRedemption_givenTokensMintedAfterDeployment(
        uint256 wrappedAmount_,
        uint256 unwrappedAmount_,
        uint256 wrappedRedeemPercentage_,
        uint256 unwrappedRedeemPercentage_
    ) public givenWrappedDerivativeIsDeployed {
        uint256 wrappedAmount = bound(wrappedAmount_, 1, AMOUNT);
        uint256 unwrappedAmount = bound(unwrappedAmount_, 1, AMOUNT);
        uint256 wrappedRedeemPercentage = bound(wrappedRedeemPercentage_, 1, 100);
        uint256 unwrappedRedeemPercentage = bound(unwrappedRedeemPercentage_, 1, 100);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, wrappedAmount);

        // Mint derivative tokens
        _mintDerivativeTokens(_alice, unwrappedAmount);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        // Redeem wrapped tokens
        uint256 redeemableWrapped = elapsed * wrappedAmount / vestingDuration;
        uint256 redeemAmountWrapped = redeemableWrapped * wrappedRedeemPercentage / 100;
        if (redeemAmountWrapped > 0) {
            vm.prank(_alice);
            linearVesting.redeem(derivativeTokenId, redeemAmountWrapped, true);
        }

        // Redeem unwrapped tokens
        uint256 redeemableUnwrapped = elapsed * unwrappedAmount / vestingDuration;
        uint256 redeemAmountUnwrapped = redeemableUnwrapped * unwrappedRedeemPercentage / 100;
        if (redeemAmountUnwrapped > 0) {
            vm.prank(_alice);
            linearVesting.redeem(derivativeTokenId, redeemAmountUnwrapped, false);
        }

        // Mint more tokens
        _mintDerivativeTokens(_alice, AMOUNT);

        // Warp to another time
        elapsed = 60_000;
        vm.warp(vestingParams.start + elapsed);

        uint256 totalAmountUnwrapped = unwrappedAmount + AMOUNT;
        uint256 expectedRedeemableUnwrapped =
            elapsed * totalAmountUnwrapped / vestingDuration - redeemAmountUnwrapped;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, false);

        // Check values
        assertEq(redeemableAmount, expectedRedeemableUnwrapped, "redeemable mismatch"); // Not affected by the other balance
    }

    function test_redeemable_wrapped_givenRedemption_givenTokensMintedAfterDeployment(
        uint256 wrappedAmount_,
        uint256 unwrappedAmount_,
        uint256 wrappedRedeemPercentage_,
        uint256 unwrappedRedeemPercentage_
    ) public givenWrappedDerivativeIsDeployed {
        uint256 wrappedAmount = bound(wrappedAmount_, 1, AMOUNT);
        uint256 unwrappedAmount = bound(unwrappedAmount_, 1, AMOUNT);
        uint256 wrappedRedeemPercentage = bound(wrappedRedeemPercentage_, 1, 100);
        uint256 unwrappedRedeemPercentage = bound(unwrappedRedeemPercentage_, 1, 100);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, wrappedAmount);

        // Mint derivative tokens
        _mintDerivativeTokens(_alice, unwrappedAmount);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        // Redeem wrapped tokens
        uint256 redeemableWrapped = elapsed * wrappedAmount / vestingDuration;
        uint256 redeemAmountWrapped = redeemableWrapped * wrappedRedeemPercentage / 100;
        if (redeemAmountWrapped > 0) {
            vm.prank(_alice);
            linearVesting.redeem(derivativeTokenId, redeemAmountWrapped, true);
        }

        // Redeem unwrapped tokens
        uint256 redeemableUnwrapped = elapsed * unwrappedAmount / vestingDuration;
        uint256 redeemAmountUnwrapped = redeemableUnwrapped * unwrappedRedeemPercentage / 100;
        if (redeemAmountUnwrapped > 0) {
            vm.prank(_alice);
            linearVesting.redeem(derivativeTokenId, redeemAmountUnwrapped, false);
        }

        // Mint wrapped tokens
        _mintWrappedDerivativeTokens(_alice, AMOUNT);

        // Warp to another time
        elapsed = 60_000;
        vm.warp(vestingParams.start + elapsed);

        uint256 totalAmountWrapped = wrappedAmount + AMOUNT;
        uint256 expectedRedeemableWrapped =
            elapsed * totalAmountWrapped / vestingDuration - redeemAmountWrapped;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId, true);

        // Check values
        assertEq(redeemableAmount, expectedRedeemableWrapped, "redeemable mismatch"); // Not affected by the other balance
    }

    function test_redeemable_wrapped_givenWrappedRedeemed_givenUnwrapped()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        uint256 vestedUnwrapped = elapsed * AMOUNT / vestingDuration;
        uint256 vestedWrapped = elapsed * AMOUNT / vestingDuration;

        // Redeem wrapped tokens - partial amount
        uint256 redeemAmountWrapped = vestedWrapped / 2;
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmountWrapped, true);

        // Unwrap the remaining wrapped tokens
        uint256 wrappedToUnwrap = AMOUNT - redeemAmountWrapped;
        vm.prank(_alice);
        linearVesting.unwrap(derivativeTokenId, wrappedToUnwrap);

        // Check the unwrapped redeemable amount
        uint256 redeemableUnwrapped = linearVesting.redeemable(_alice, derivativeTokenId, false);
        assertEq(
            redeemableUnwrapped, vestedUnwrapped + wrappedToUnwrap, "unwrapped: redeemable mismatch"
        );

        // Check the wrapped redeemable amount
        uint256 redeemableWrapped = linearVesting.redeemable(_alice, derivativeTokenId, true);
        assertEq(redeemableWrapped, 0, "wrapped: redeemable mismatch");

        // Warp to another time
        elapsed = 60_000;
        vm.warp(vestingParams.start + elapsed);

        vestedUnwrapped = elapsed * AMOUNT / vestingDuration;
        vestedWrapped = elapsed * wrappedToUnwrap / vestingDuration;

        // Check the unwrapped redeemable amount
        redeemableUnwrapped = linearVesting.redeemable(_alice, derivativeTokenId, false);
        assertEq(
            redeemableUnwrapped, vestedUnwrapped + vestedWrapped, "unwrapped: redeemable mismatch"
        );

        // Check the wrapped redeemable amount
        redeemableWrapped = linearVesting.redeemable(_alice, derivativeTokenId, true);
        assertEq(redeemableWrapped, 0, "wrapped: redeemable mismatch");
    }

    function test_redeemable_unwrapped_givenUnwrappedRedeemed_givenWrapped()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        uint256 vestedUnwrapped = elapsed * AMOUNT / vestingDuration;
        uint256 vestedWrapped = elapsed * AMOUNT / vestingDuration;

        // Redeem unwrapped tokens - partial amount
        uint256 redeemAmountUnwrapped = vestedUnwrapped / 2;
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmountUnwrapped, false);

        // Wrap the remaining unwrapped tokens
        uint256 unwrappedToWrap = AMOUNT - redeemAmountUnwrapped;
        vm.prank(_alice);
        linearVesting.wrap(derivativeTokenId, unwrappedToWrap);

        // Check the unwrapped redeemable amount
        uint256 redeemableUnwrapped = linearVesting.redeemable(_alice, derivativeTokenId, false);
        assertEq(redeemableUnwrapped, 0, "unwrapped: redeemable mismatch after wrap");

        // Check the wrapped redeemable amount
        uint256 redeemableWrapped = linearVesting.redeemable(_alice, derivativeTokenId, true);
        assertEq(
            redeemableWrapped,
            vestedWrapped + unwrappedToWrap,
            "wrapped: redeemable mismatch after wrap"
        );

        // Warp to another time
        elapsed = 60_000;
        vm.warp(vestingParams.start + elapsed);

        vestedUnwrapped = elapsed * unwrappedToWrap / vestingDuration;
        vestedWrapped = elapsed * AMOUNT / vestingDuration;

        // Check the unwrapped redeemable amount
        redeemableUnwrapped = linearVesting.redeemable(_alice, derivativeTokenId, false);
        assertEq(redeemableUnwrapped, 0, "unwrapped: redeemable mismatch");

        // Check the wrapped redeemable amount
        redeemableWrapped = linearVesting.redeemable(_alice, derivativeTokenId, true);
        assertEq(redeemableWrapped, vestedUnwrapped + vestedWrapped, "wrapped: redeemable mismatch");
    }

    function test_redeemable_unwrapped_givenUnwrappedRedeemed_givenPartialWrapped()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(vestingParams.start + elapsed);

        uint256 vestedUnwrapped = elapsed * AMOUNT / vestingDuration;

        // Redeem unwrapped tokens - partial amount
        uint256 redeemAmountUnwrapped = vestedUnwrapped / 2;
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmountUnwrapped, false);

        // Wrap some of the remaining unwrapped tokens
        uint256 unwrappedToWrap = (AMOUNT - redeemAmountUnwrapped) / 2;
        vm.prank(_alice);
        linearVesting.wrap(derivativeTokenId, unwrappedToWrap);

        // Check the unwrapped redeemable amount
        uint256 redeemableUnwrapped = linearVesting.redeemable(_alice, derivativeTokenId, false);
        assertEq(
            redeemableUnwrapped,
            elapsed * (AMOUNT - unwrappedToWrap) / vestingDuration - redeemAmountUnwrapped,
            "unwrapped: redeemable mismatch after wrap"
        );

        // Check the wrapped redeemable amount
        uint256 redeemableWrapped = linearVesting.redeemable(_alice, derivativeTokenId, true);
        assertEq(
            redeemableWrapped,
            elapsed * (AMOUNT + unwrappedToWrap) / vestingDuration,
            "wrapped: redeemable mismatch after wrap"
        );

        // Warp to another time
        elapsed = 60_000;
        vm.warp(vestingParams.start + elapsed);

        // Check the unwrapped redeemable amount
        redeemableUnwrapped = linearVesting.redeemable(_alice, derivativeTokenId, false);
        assertEq(
            redeemableUnwrapped,
            elapsed * (AMOUNT - unwrappedToWrap) / vestingDuration - redeemAmountUnwrapped,
            "unwrapped: redeemable mismatch"
        );

        // Check the wrapped redeemable amount
        redeemableWrapped = linearVesting.redeemable(_alice, derivativeTokenId, true);
        assertEq(
            redeemableWrapped,
            elapsed * (AMOUNT + unwrappedToWrap) / vestingDuration,
            "wrapped: redeemable mismatch"
        );
    }

    // wrap
    // [X] when the token id does not exist
    //  [X] it reverts
    // [X] when the amount is 0
    //  [X] it reverts
    // [X] when the caller has insufficient balance of the derivative token
    //  [X] it reverts
    // [X] given the wrapped token has not been deployed
    //  [X] it deploys the wrapped token, burns the derivative token and mints the wrapped token
    // [X] given the wrapped token has been deployed
    //  [X] it burns the derivative token and mints the wrapped token

    function test_wrap_givenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.wrap(derivativeTokenId, AMOUNT);
    }

    function test_wrap_givenAmountIsZero_reverts()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.wrap(derivativeTokenId, 0);
    }

    function test_wrap_givenInsufficientBalance_reverts() public givenDerivativeIsDeployed {
        // Expect revert (underflow)
        vm.expectRevert();

        // Call
        vm.prank(_alice);
        linearVesting.wrap(derivativeTokenId, AMOUNT);
    }

    function test_wrap_givenWrappedTokenNotDeployed(uint256 wrapAmount_)
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        uint256 wrapAmount = bound(wrapAmount_, 1, AMOUNT);

        // Call
        vm.prank(_alice);
        linearVesting.wrap(derivativeTokenId, wrapAmount);

        // Get the token metadata
        Derivative.Token memory tokenMetadata = linearVesting.getTokenMetadata(derivativeTokenId);

        // Check values
        assertEq(
            linearVesting.balanceOf(_alice, derivativeTokenId),
            AMOUNT - wrapAmount,
            "derivative: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(tokenMetadata.wrapped).balanceOf(_alice),
            wrapAmount,
            "wrapped derivative: balanceOf mismatch"
        );

        // Check total supply
        assertEq(
            linearVesting.totalSupply(derivativeTokenId),
            AMOUNT - wrapAmount,
            "derivative: totalSupply mismatch"
        );
        assertEq(
            SoulboundCloneERC20(tokenMetadata.wrapped).totalSupply(),
            wrapAmount,
            "wrapped derivative: totalSupply mismatch"
        );
    }

    function test_wrap_givenWrappedTokenDeployed(uint256 wrapAmount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        uint256 wrapAmount = bound(wrapAmount_, 1, AMOUNT);

        // Call
        vm.prank(_alice);
        linearVesting.wrap(derivativeTokenId, wrapAmount);

        // Check values
        assertEq(
            linearVesting.balanceOf(_alice, derivativeTokenId),
            AMOUNT - wrapAmount,
            "derivative: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice),
            wrapAmount,
            "wrapped derivative: balanceOf mismatch"
        );

        // Check total supply
        assertEq(
            linearVesting.totalSupply(derivativeTokenId),
            AMOUNT - wrapAmount,
            "derivative: totalSupply mismatch"
        );
        assertEq(
            SoulboundCloneERC20(derivativeWrappedAddress).totalSupply(),
            wrapAmount,
            "wrapped derivative: totalSupply mismatch"
        );
    }

    // unwrap
    // [X] when the token id does not exist
    //  [X] it reverts
    // [X] when the amount is 0
    //  [X] it reverts
    // [X] given the wrapped token has not been deployed
    //  [X] it reverts
    // [X] when the caller has insufficient balance of the wrapped token
    //  [X] it reverts
    // [X] it burns the wrapped token and mints the derivative token

    function test_unwrap_givenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.unwrap(derivativeTokenId, AMOUNT);
    }

    function test_unwrap_givenAmountIsZero_reverts()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.unwrap(derivativeTokenId, 0);
    }

    function test_unwrap_givenWrappedTokenNotDeployed() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.unwrap(derivativeTokenId, AMOUNT);
    }

    function test_unwrap_givenInsufficientBalance_reverts()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Expect revert (underflow)
        vm.expectRevert();

        // Call
        vm.prank(_alice);
        linearVesting.unwrap(derivativeTokenId, AMOUNT);
    }

    function test_unwrap(uint256 unwrapAmount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        uint256 unwrapAmount = bound(unwrapAmount_, 1, AMOUNT);

        // Call
        vm.prank(_alice);
        linearVesting.unwrap(derivativeTokenId, unwrapAmount);

        // Check values
        assertEq(
            linearVesting.balanceOf(_alice, derivativeTokenId),
            unwrapAmount,
            "derivative: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice),
            AMOUNT - unwrapAmount,
            "wrapped derivative: balanceOf mismatch"
        );

        // Check total supply
        assertEq(
            linearVesting.totalSupply(derivativeTokenId),
            unwrapAmount,
            "derivative: totalSupply mismatch"
        );
        assertEq(
            SoulboundCloneERC20(derivativeWrappedAddress).totalSupply(),
            AMOUNT - unwrapAmount,
            "wrapped derivative: totalSupply mismatch"
        );
    }

    // name
    // [X] when the token id is invalid
    //  [X] it reverts
    // [X] it returns the name

    function test_name_givenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.name(derivativeTokenId);
    }

    function test_name() public givenDerivativeIsDeployed {
        // Call
        string memory name = linearVesting.name(derivativeTokenId);

        // Check values
        assertEq(name, wrappedDerivativeTokenName);
    }

    // symbol
    // [X] when the token id is invalid
    //  [X] it reverts
    // [X] it returns the symbol

    function test_symbol_givenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.symbol(derivativeTokenId);
    }

    function test_symbol() public givenDerivativeIsDeployed {
        // Call
        string memory symbol = linearVesting.symbol(derivativeTokenId);

        // Check values
        assertEq(symbol, wrappedDerivativeTokenSymbol);
    }

    // decimals
    // [X] when the token id is invalid
    //  [X] it reverts
    // [ X] it returns the decimals of the underlying base token

    function test_decimals_givenTokenIdDoesNotExist_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.decimals(derivativeTokenId);
    }

    function test_decimals() public givenDerivativeIsDeployed {
        // Call
        uint8 decimals = linearVesting.decimals(derivativeTokenId);

        // Check values
        assertEq(decimals, underlyingTokenDecimals);
    }

    // balanceOf
    // [X] when the token id is invalid
    //  [X] it returns 0
    // [X] it returns the balance of the unwrapped derivative token

    function test_balanceOf_givenTokenIdDoesNotExist() public {
        // Call
        uint256 balance = linearVesting.balanceOf(_alice, derivativeTokenId);

        // Check values
        assertEq(balance, 0);
    }

    function test_balanceOf(uint256 amount_) public givenWrappedDerivativeIsDeployed {
        uint256 amount = bound(amount_, 0, AMOUNT);

        // Mint
        if (amount > 0) {
            _mintDerivativeTokens(_alice, amount);
        }

        // Call
        uint256 balance = linearVesting.balanceOf(_alice, derivativeTokenId);

        // Check values
        assertEq(balance, amount);
    }

    function test_balanceOf_wrapped(uint256 amount_) public givenWrappedDerivativeIsDeployed {
        uint256 amount = bound(amount_, 0, AMOUNT);

        // Mint
        if (amount > 0) {
            _mintWrappedDerivativeTokens(_alice, amount);
        }

        // Call
        uint256 balance = linearVesting.balanceOf(_alice, derivativeTokenId);

        // Check values
        assertEq(balance, 0);
    }

    // totalSupply
    // [X] when the token id is invalid
    //  [X] it returns 0
    // [X] it returns the total supply of the unwrapped derivative token

    function test_totalSupply_givenTokenIdDoesNotExist() public {
        // Call
        uint256 balance = linearVesting.totalSupply(derivativeTokenId);

        // Check values
        assertEq(balance, 0);
    }

    function test_totalSupply(uint256 amount_) public givenWrappedDerivativeIsDeployed {
        uint256 amount = bound(amount_, 0, AMOUNT);

        // Mint
        if (amount > 0) {
            _mintDerivativeTokens(_alice, amount);
        }

        // Call
        uint256 totalSupply = linearVesting.totalSupply(derivativeTokenId);

        // Check values
        assertEq(totalSupply, amount);
    }

    function test_totalSupply_wrapped(uint256 amount_) public givenWrappedDerivativeIsDeployed {
        uint256 amount = bound(amount_, 0, AMOUNT);

        // Mint
        if (amount > 0) {
            _mintWrappedDerivativeTokens(_alice, amount);
        }

        // Call
        uint256 totalSupply = linearVesting.totalSupply(derivativeTokenId);

        // Check values
        assertEq(totalSupply, 0);
    }

    // reclaim
    // [X] it reverts

    function test_reclaim_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.reclaim(derivativeTokenId);
    }

    // transfer
    // [X] it reverts

    function test_transfer_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.NotPermitted.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.transfer(address(0x4), derivativeTokenId, AMOUNT);
    }

    // transferFrom
    // [X] it reverts

    function test_transferFrom_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.NotPermitted.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.transferFrom(_alice, address(0x4), derivativeTokenId, AMOUNT);
    }

    // approve
    // [X] it reverts

    function test_approve_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.NotPermitted.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.approve(address(0x4), derivativeTokenId, AMOUNT);
    }

    // exerciseCost
    // [X] it reverts

    function test_exerciseCost_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.exerciseCost(bytes(""), derivativeTokenId);
    }

    // convertsTo
    // [X] it reverts

    function test_convertsTo_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.convertsTo(bytes(""), derivativeTokenId);
    }

    // transform
    // [X] it reverts

    function test_transform_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.transform(derivativeTokenId, _alice, AMOUNT, false);
    }

    // exercise
    // [X] it reverts

    function test_exercise_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.exercise(derivativeTokenId, AMOUNT, false);
    }
}
