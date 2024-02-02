// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {StringHelper} from "test/lib/String.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";
import {SoulboundCloneERC20} from "src/modules/derivatives/SoulboundCloneERC20.sol";

contract LinearVestingTest is Test, Permit2User {
    using StringHelper for string;

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

    uint256 internal constant AMOUNT = 1e18;

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
    //  [X] it reverts
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
        assertEq(wrappedDerivative.teller(), address(linearVesting));
        assertEq(wrappedDerivative.owner(), address(linearVesting));
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
        assertEq(wrappedDerivative.teller(), address(linearVesting));
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
        assertEq(wrappedDerivative.teller(), address(linearVesting));
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
        assertEq(wrappedDerivative.teller(), address(linearVesting));
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

    function test_validate_startAndExpiryTimestampsAreTheSame()
        public
        whenStartAndExpiryTimestampsAreTheSame
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

    function test_validate() public {
        // Call
        bool isValid = linearVesting.validate(vestingParamsBytes);

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
        vm.expectRevert();

        // Call
        linearVesting.computeId(vestingParamsBytes);
    }

    function test_computeId_paramsChanged()
        public
        givenDerivativeIsDeployed
        whenVestingParamsAreChanged
    {
        // Call
        uint256 tokenId = linearVesting.computeId(vestingParamsBytes);

        // Check values
        assertFalse(tokenId == derivativeTokenId);
    }

    function test_computeId() public givenDerivativeIsDeployed {
        // Call
        uint256 tokenId = linearVesting.computeId(vestingParamsBytes);

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
    //  [X] it reverts
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

    function test_mint_params_startTimestampIsBeforeCurrentTimestamp_reverts()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
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

    function test_mint_params_mintAmountIsZero_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(_alice, underlyingTokenAddress, vestingParamsBytes, 0, false);
    }

    function test_mint_params_recipientIsZero_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(auctionHouse));
        linearVesting.mint(address(0), underlyingTokenAddress, vestingParamsBytes, AMOUNT, false);
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
    // [ ] when the derivative is minted after start timestamp
    //  [ ] given tokens have been redeemed
    //   [ ] it returns the remaining redeemable amount
    //  [ ] it returns the full balance

    // reclaim
    // [ ] it reverts

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
