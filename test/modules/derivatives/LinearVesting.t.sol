// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Libraries
import {Test} from "forge-std/Test.sol";

import {Permit2User} from "test/lib/permit2/Permit2User.sol";
import {StringHelper} from "test/lib/String.sol";
import {MockFeeOnTransferERC20} from "test/lib/mocks/MockFeeOnTransferERC20.sol";
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

    MockFeeOnTransferERC20 internal underlyingToken;
    address internal underlyingTokenAddress;
    uint8 internal underlyingTokenDecimals = 18;

    AuctionHouse internal auctionHouse;
    LinearVesting internal linearVesting;

    LinearVesting.VestingParams internal vestingParams;
    bytes internal vestingParamsBytes;
    uint48 internal constant vestingExpiry = 1_705_055_144; // 2024-01-12
    uint48 internal constant vestingDuration = 2 days;

    uint256 internal constant AMOUNT = 1e18;

    uint256 internal constant VESTING_DATA_LEN = 64; // length + 1 slot for expiry

    uint256 internal derivativeTokenId;
    address internal derivativeWrappedAddress;
    string internal wrappedDerivativeTokenName;
    string internal wrappedDerivativeTokenSymbol;
    uint256 internal wrappedDerivativeTokenNameLength;
    uint256 internal wrappedDerivativeTokenSymbolLength;

    function setUp() public {
        // Wrap to reasonable timestamp
        vm.warp(1_704_882_344);

        underlyingToken =
            new MockFeeOnTransferERC20("Underlying", "UNDERLYING", underlyingTokenDecimals);
        underlyingTokenAddress = address(underlyingToken);

        auctionHouse = new AuctionHouse(address(this), _protocol, _PERMIT2_ADDRESS);
        linearVesting = new LinearVesting(address(auctionHouse));
        auctionHouse.installModule(linearVesting);

        vestingParams = LinearVesting.VestingParams({expiry: vestingExpiry});
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
        underlyingToken =
            new MockFeeOnTransferERC20("Underlying2", "UNDERLYING2", underlyingTokenDecimals);
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

    modifier givenUnderlyingTokenIsFeeOnTransfer() {
        underlyingToken.setTransferFee(100);
        _;
    }

    // ========== TESTS ========== //

    // deploy
    // [X] when the vesting params are in the incorrect format
    //  [X] it reverts
    // [X] when the underlying token is 0
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
    // [X] when the expiry timestamp is before the current timestamp
    //  [X] it reverts
    // [X] when the mint amount is 0
    //  [X] it reverts
    // [X] when the recipient is 0
    //  [X] it succeeds
    // [X] given the caller has an insufficient balance of the underlying token
    //  [X] it reverts
    // [X] given the underlying token is fee-on-transfer
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

    function test_mint_params_feeOnTransfer_reverts()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
        givenUnderlyingTokenIsFeeOnTransfer
        givenDerivativeIsDeployed
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LinearVesting.UnsupportedToken.selector, underlyingTokenAddress);
        vm.expectRevert(err);

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
    // [X] given the underlying token is fee-on-transfer
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

    function test_mint_tokenId_feeOnTransfer_reverts()
        public
        givenParentHasUnderlyingTokenBalance(AMOUNT)
        givenUnderlyingTokenIsFeeOnTransfer
        givenDerivativeIsDeployed
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LinearVesting.UnsupportedToken.selector, underlyingTokenAddress);
        vm.expectRevert(err);

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
        linearVesting.redeem(derivativeTokenId, AMOUNT);
    }

    function test_redeem_givenRedeemAmountIsZero_reverts() public givenDerivativeIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, 0);
    }

    function test_redeem_givenAmountGreaterThanRedeemable_reverts(uint48 elapsed_)
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        // Warp to mid-way, so not all tokens are vested
        uint48 elapsed = uint48(bound(elapsed_, 1, vestingDuration - 1));
        vm.warp(block.timestamp + elapsed);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, AMOUNT);
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
        linearVesting.redeem(derivativeTokenId, AMOUNT);
    }

    function test_redeem_givenWrappedTokenNotDeployed(uint256 amount_)
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, amount);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), AMOUNT - amount);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), amount);
    }

    function test_redeem_givenWrappedBalance(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, amount);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), AMOUNT - amount);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), amount);
    }

    function test_redeem_givenUnwrappedBalance(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, amount);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), AMOUNT - amount);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), 0);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), amount);
    }

    function test_redeem_givenMixedBalance()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amountToRedeem = AMOUNT + 1;

        // Call
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, amountToRedeem);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0); // Redeems unwrapped first
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), AMOUNT - 1);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), amountToRedeem);
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
        linearVesting.redeemMax(derivativeTokenId);
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
        linearVesting.redeemMax(derivativeTokenId);
    }

    function test_redeemMax_givenWrappedTokenNotDeployed()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), AMOUNT);
    }

    function test_redeemMax_givenWrappedBalance_givenVestingExpiry()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), 0);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), AMOUNT);
    }

    function test_redeemMax_givenUnwrappedBalance_givenVestingExpiry()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId);

        // Check values
        assertEq(linearVesting.balanceOf(_alice, derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice), 0);
        assertEq(SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice), AMOUNT);
    }

    function test_redeemMax(uint48 elapsed_) public givenWrappedDerivativeIsDeployed {
        // Mint both wrapped and unwrapped
        _mintDerivativeTokens(_alice, AMOUNT);
        _mintWrappedDerivativeTokens(_alice, AMOUNT);

        // Warp during vesting
        uint48 elapsed = uint48(bound(elapsed_, 1, vestingDuration - 1));
        vm.warp(block.timestamp + elapsed);

        uint256 redeemable = (AMOUNT + AMOUNT) * elapsed / vestingDuration;
        uint256 expectedBalanceUnwrapped;
        uint256 expectedBalanceWrapped;
        if (redeemable < AMOUNT) {
            expectedBalanceUnwrapped = AMOUNT - redeemable;
            expectedBalanceWrapped = AMOUNT;
        } else {
            expectedBalanceUnwrapped = 0;
            expectedBalanceWrapped = AMOUNT - (redeemable - AMOUNT);
        }

        // Call
        vm.prank(_alice);
        linearVesting.redeemMax(derivativeTokenId);

        // Check values
        assertEq(
            linearVesting.balanceOf(_alice, derivativeTokenId),
            expectedBalanceUnwrapped,
            "derivative token: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice),
            expectedBalanceWrapped,
            "wrapped derivative token: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(underlyingTokenAddress).balanceOf(_alice),
            redeemable,
            "underlying token: balanceOf mismatch"
        );
    }

    // redeemable
    // [X] when the token id does not exist
    //  [X] it reverts
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
        linearVesting.redeemable(_alice, derivativeTokenId);
    }

    function test_redeemable_givenAfterExpiry()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, AMOUNT);
    }

    function test_redeemable_givenWrappedTokenNotDeployed()
        public
        givenDerivativeIsDeployed
        givenAfterVestingExpiry
    {
        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, 0);
    }

    function test_redeemable_givenBeforeExpiry(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        uint256 amount = bound(amount_, 1, AMOUNT);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, amount);

        // Warp to before expiry
        uint48 elapsed = 100_000;
        vm.warp(block.timestamp + elapsed);

        // Includes wrapped and unwrapped balances
        uint256 expectedRedeemable = elapsed * (AMOUNT + amount) / vestingDuration;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable);
    }

    function test_redeemable_givenRedemption(
        uint256 wrappedAmount_,
        uint256 unwrappedAmount_,
        uint256 redeemPercentage_
    ) public givenWrappedDerivativeIsDeployed {
        uint256 wrappedAmount = bound(wrappedAmount_, 1e9, AMOUNT);
        uint256 unwrappedAmount = bound(unwrappedAmount_, 1e9, AMOUNT);
        uint256 redeemPercentage = bound(redeemPercentage_, 1, 100);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, wrappedAmount);

        // Mint derivative tokens
        _mintDerivativeTokens(_alice, unwrappedAmount);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(block.timestamp + elapsed);

        // Calculate redeemable amount
        uint256 redeemable = elapsed * (wrappedAmount + unwrappedAmount) / vestingDuration;
        uint256 amountToRedeem = redeemable * redeemPercentage / 100;

        // Redeem
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, amountToRedeem);

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, redeemable - amountToRedeem, "redeemable mismatch");
    }

    function test_redeemable_redemptions() public givenWrappedDerivativeIsDeployed {
        // Mint tokens
        _mintDerivativeTokens(_alice, AMOUNT);
        _mintWrappedDerivativeTokens(_alice, AMOUNT);

        // Warp to before expiry
        uint48 start = uint48(block.timestamp);
        uint48 elapsed = 50_000;
        vm.warp(start + elapsed);

        // Calculate the vested amount
        uint256 vestedAmount = (elapsed * (AMOUNT + AMOUNT)) / vestingDuration;
        uint256 claimedAmount = 0;
        uint256 redeemableAmount = vestedAmount - claimedAmount;

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId),
            redeemableAmount,
            "1: redeemable mismatch"
        );

        // Redeem half the tokens
        uint256 redeemAmount = redeemableAmount / 2;
        claimedAmount += redeemAmount;
        redeemableAmount = vestedAmount - claimedAmount;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId),
            redeemableAmount,
            "2: redeemable mismatch"
        );

        // Redeem the remaining tokens
        redeemAmount = redeemableAmount;
        claimedAmount += redeemAmount;
        redeemableAmount = 0;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId),
            redeemableAmount,
            "3: redeemable mismatch"
        );

        // Check that the claimed amount is the same as the vested amount
        assertEq(claimedAmount, vestedAmount, "claimedAmount mismatch");

        // Warp to another time
        elapsed = 60_000;
        vm.warp(start + elapsed);

        // Calculate the vested amount
        vestedAmount = elapsed * (AMOUNT + AMOUNT) / vestingDuration;
        redeemableAmount = vestedAmount - claimedAmount;

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId),
            redeemableAmount,
            "4: redeemable mismatch"
        );

        // Redeem half the tokens
        redeemAmount = redeemableAmount / 2;
        claimedAmount += redeemAmount;
        redeemableAmount = vestedAmount - claimedAmount;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId),
            redeemableAmount,
            "5: redeemable mismatch"
        );

        // Redeem the remaining tokens
        redeemAmount = redeemableAmount;
        claimedAmount += redeemAmount;
        redeemableAmount = 0;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount);

        assertEq(
            linearVesting.redeemable(_alice, derivativeTokenId),
            redeemableAmount,
            "6: redeemable mismatch"
        );

        // Check that the claimed amount is the same as the vested amount
        assertEq(claimedAmount, vestedAmount, "claimedAmount mismatch");
    }

    function test_redeemable_givenTokensMintedAfterDeployment(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        uint256 amount = bound(amount_, 1e9, AMOUNT);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(block.timestamp + elapsed);

        // Mint tokens, claims all redeemable tokens at the same time
        _mintDerivativeTokens(_alice, amount);

        uint256 expectedRedeemable = 0;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable);
    }

    function test_redeemable_givenWrappedTokensMintedAfterDeployment(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
    {
        uint256 amount = bound(amount_, 1e9, AMOUNT);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(block.timestamp + elapsed);

        // Mint tokens, claims all redeemable tokens at the same time
        _mintWrappedDerivativeTokens(_alice, amount);

        uint256 expectedRedeemable = 0;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable);
    }

    function test_redeemable_givenRedemption_givenTokensMintedAfterDeployment(
        uint256 wrappedAmount_,
        uint256 unwrappedAmount_,
        uint256 redeemPercentage_
    ) public givenWrappedDerivativeIsDeployed {
        uint256 wrappedAmount = bound(wrappedAmount_, 1e9, AMOUNT);
        uint256 unwrappedAmount = bound(unwrappedAmount_, 1e9, AMOUNT);
        uint256 redeemPercentage = bound(redeemPercentage_, 1, 100);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_alice, wrappedAmount);

        // Mint derivative tokens
        _mintDerivativeTokens(_alice, unwrappedAmount);

        // Warp to before expiry
        uint48 start = uint48(block.timestamp);
        uint48 elapsed = 50_000;
        vm.warp(start + elapsed);

        // Redeem wrapped tokens
        uint256 redeemable = elapsed * (wrappedAmount + unwrappedAmount) / vestingDuration;
        uint256 amountToRedeem = redeemable * redeemPercentage / 100;

        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, amountToRedeem);

        // Mint more tokens
        // This claims all the redeemable tokens
        _mintDerivativeTokens(_alice, AMOUNT);
        _mintWrappedDerivativeTokens(_alice, AMOUNT);

        // Warp to another time
        elapsed = 60_000;
        vm.warp(start + elapsed);

        // Calculate the vested amount
        uint256 vestedAmount = (elapsed - 50_000)
            * (AMOUNT + AMOUNT + unwrappedAmount + wrappedAmount - redeemable)
            / (vestingDuration - 50_000);
        uint256 claimedAmount = 0;
        uint256 expectedRedeemableAmount = vestedAmount - claimedAmount;

        // Call
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");
    }

    function test_redeemable_givenRedemption_givenUnwrapped()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        // Warp to before expiry
        uint48 start = uint48(block.timestamp);
        uint48 elapsed = 50_000;
        vm.warp(start + elapsed);

        uint256 vested = (AMOUNT + AMOUNT).mulDivDown(elapsed, vestingDuration);

        // Redeem tokens - partial amount
        uint256 redeemAmount = 1e9;
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount);

        // Unwrap half of the remaining wrapped tokens
        uint256 wrappedToUnwrap =
            SoulboundCloneERC20(derivativeWrappedAddress).balanceOf(_alice) / 2;
        vm.prank(_alice);
        linearVesting.unwrap(derivativeTokenId, wrappedToUnwrap);

        uint256 expectedRedeemableAmount = vested - redeemAmount;

        // Check the redeemable amount
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");

        // Warp to another time
        elapsed = 60_000;
        vm.warp(start + elapsed);

        vested = (AMOUNT + AMOUNT).mulDivDown(elapsed, vestingDuration);
        expectedRedeemableAmount = vested - redeemAmount;

        // Check the redeemable amount
        redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");
    }

    function test_redeemable_givenRedemption_givenWrapped()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(AMOUNT)
        givenAliceHasWrappedDerivativeTokens(AMOUNT)
    {
        // Warp to before expiry
        uint48 start = uint48(block.timestamp);
        uint48 elapsed = 50_000;
        vm.warp(start + elapsed);

        uint256 vested = (AMOUNT + AMOUNT).mulDivDown(elapsed, vestingDuration);

        // Redeem tokens - partial amount
        uint256 redeemAmount = vested / 4;
        vm.prank(_alice);
        linearVesting.redeem(derivativeTokenId, redeemAmount);

        // Wrap half of the remaining unwrapped tokens
        uint256 unwrappedToWrap = linearVesting.balanceOf(_alice, derivativeTokenId) / 2;
        vm.prank(_alice);
        linearVesting.wrap(derivativeTokenId, unwrappedToWrap);

        uint256 expectedRedeemableAmount = vested - redeemAmount;

        // Check the redeemable amount
        uint256 redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");

        // Warp to another time
        elapsed = 60_000;
        vm.warp(start + elapsed);

        vested = (AMOUNT + AMOUNT).mulDivDown(elapsed, vestingDuration);
        expectedRedeemableAmount = vested - redeemAmount;

        // Check the redeemable amount
        redeemableAmount = linearVesting.redeemable(_alice, derivativeTokenId);
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");
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
        linearVesting.transform(derivativeTokenId, _alice, AMOUNT);
    }

    // exercise
    // [X] it reverts

    function test_exercise_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        linearVesting.exercise(derivativeTokenId, AMOUNT);
    }
}
