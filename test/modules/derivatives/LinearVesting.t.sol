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

    address internal constant _SELLER = address(0x1);
    address internal constant _PROTOCOL = address(0x2);
    address internal constant _ALICE = address(0x3);

    MockFeeOnTransferERC20 internal _underlyingToken;
    address internal _underlyingTokenAddress;
    uint8 internal _underlyingTokenDecimals = 18;

    AuctionHouse internal _auctionHouse;
    LinearVesting internal _linearVesting;

    LinearVesting.VestingParams internal _vestingParams;
    bytes internal _vestingParamsBytes;
    uint48 internal constant _VESTING_START = 1_704_882_344; // 2024-01-10
    uint48 internal constant _VESTING_EXPIRY = 1_705_055_144; // 2024-01-12
    uint48 internal constant _VESTING_DURATION = _VESTING_EXPIRY - _VESTING_START;

    uint256 internal constant _AMOUNT = 1e18;
    uint256 internal constant _AMOUNT_TWO = 2e18;

    uint256 internal constant _VESTING_DATA_LEN = 96; // length + 1 slot for expiry + 1 slot for start

    uint256 internal _derivativeTokenId;
    address internal _derivativeWrappedAddress;
    string internal _wrappedDerivativeTokenName;
    string internal _wrappedDerivativeTokenSymbol;
    uint256 internal _wrappedDerivativeTokenNameLength;
    uint256 internal _wrappedDerivativeTokenSymbolLength;

    function setUp() public {
        // Warp to before vesting start
        vm.warp(_VESTING_START - 1);

        _underlyingToken =
            new MockFeeOnTransferERC20("Underlying", "UNDERLYING", _underlyingTokenDecimals);
        _underlyingTokenAddress = address(_underlyingToken);

        _auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _linearVesting = new LinearVesting(address(_auctionHouse));
        _auctionHouse.installModule(_linearVesting);

        _vestingParams =
            LinearVesting.VestingParams({start: _VESTING_START, expiry: _VESTING_EXPIRY});
        _vestingParamsBytes = abi.encode(_vestingParams);

        _wrappedDerivativeTokenName = "Underlying 2024-01-12";
        _wrappedDerivativeTokenSymbol = "UNDERLYING 2024-01-12";
        _wrappedDerivativeTokenNameLength = bytes(_wrappedDerivativeTokenName).length;
        _wrappedDerivativeTokenSymbolLength = bytes(_wrappedDerivativeTokenSymbol).length;
    }

    // ========== MODIFIERS ========== //

    modifier givenVestingParamsAreInvalid() {
        _vestingParamsBytes = abi.encode("junk");
        _;
    }

    modifier whenUnderlyingTokenIsZero() {
        _underlyingTokenAddress = address(0);
        _;
    }

    modifier whenStartTimestampIsZero() {
        _vestingParams.start = 0;
        _vestingParamsBytes = abi.encode(_vestingParams);
        _;
    }

    modifier whenExpiryTimestampIsZero() {
        _vestingParams.expiry = 0;
        _vestingParamsBytes = abi.encode(_vestingParams);
        _;
    }

    modifier whenStartAndExpiryTimestampsAreTheSame() {
        _vestingParams.expiry = _vestingParams.start;
        _vestingParamsBytes = abi.encode(_vestingParams);
        _;
    }

    modifier whenStartTimestampIsAfterExpiryTimestamp() {
        _vestingParams.start = _vestingParams.expiry + 1;
        _vestingParamsBytes = abi.encode(_vestingParams);
        _;
    }

    modifier whenStartTimestampIsBeforeCurrentTimestamp() {
        _vestingParams.start = uint48(block.timestamp) - 1;
        _vestingParamsBytes = abi.encode(_vestingParams);
        _;
    }

    modifier whenExpiryTimestampIsBeforeCurrentTimestamp() {
        _vestingParams.expiry = uint48(block.timestamp) - 1;
        _vestingParamsBytes = abi.encode(_vestingParams);
        _;
    }

    modifier whenVestingParamsAreChanged() {
        _vestingParams.expiry = 1_705_227_944; // 2024-01-14
        _vestingParamsBytes = abi.encode(_vestingParams);

        _wrappedDerivativeTokenName = "Underlying 2024-01-14";
        _wrappedDerivativeTokenSymbol = "UNDERLYING 2024-01-14";
        _wrappedDerivativeTokenNameLength = bytes(_wrappedDerivativeTokenName).length;
        _wrappedDerivativeTokenSymbolLength = bytes(_wrappedDerivativeTokenSymbol).length;
        _;
    }

    modifier whenUnderlyingTokenIsChanged() {
        _underlyingTokenDecimals = 17;
        _underlyingToken =
            new MockFeeOnTransferERC20("Underlying2", "UNDERLYING2", _underlyingTokenDecimals);
        _underlyingTokenAddress = address(_underlyingToken);

        _wrappedDerivativeTokenName = "Underlying2 2024-01-12";
        _wrappedDerivativeTokenSymbol = "UNDERLYING2 2024-01-12";
        _wrappedDerivativeTokenNameLength = bytes(_wrappedDerivativeTokenName).length;
        _wrappedDerivativeTokenSymbolLength = bytes(_wrappedDerivativeTokenSymbol).length;
        _;
    }

    modifier givenDerivativeIsDeployed() {
        (_derivativeTokenId, _derivativeWrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);

        assertTrue(_derivativeTokenId > 0);
        assertTrue(_derivativeWrappedAddress == address(0));
        _;
    }

    modifier givenWrappedDerivativeIsDeployed() {
        (_derivativeTokenId, _derivativeWrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

        assertTrue(_derivativeTokenId > 0);
        assertTrue(_derivativeWrappedAddress != address(0));
        _;
    }

    modifier givenParentHasUnderlyingTokenBalance(uint256 balance_) {
        _underlyingToken.mint(address(_auctionHouse), balance_);

        vm.prank(address(_auctionHouse));
        _underlyingToken.approve(address(_linearVesting), balance_);
        _;
    }

    modifier givenCallerHasUnderlyingTokenBalance(address caller_, uint256 balance_) {
        _underlyingToken.mint(caller_, balance_);

        vm.prank(address(caller_));
        _underlyingToken.approve(address(_linearVesting), balance_);
        _;
    }

    modifier givenBeforeVestingStart() {
        vm.warp(_VESTING_START - 1);
        _;
    }

    modifier givenAfterVestingExpiry() {
        vm.warp(_VESTING_EXPIRY + 1);
        _;
    }

    function _mintDerivativeTokens(address recipient_, uint256 amount_) internal {
        // Mint underlying tokens for transfer
        _underlyingToken.mint(address(_auctionHouse), amount_);

        // Approve spending of underlying tokens (which is done in the AuctionHouse)
        vm.prank(address(_auctionHouse));
        _underlyingToken.approve(address(_linearVesting), amount_);

        // Mint derivative tokens
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(
            recipient_, _underlyingTokenAddress, _vestingParamsBytes, amount_, false
        );
    }

    modifier givenAliceHasDerivativeTokens(uint256 amount_) {
        _mintDerivativeTokens(_ALICE, amount_);
        _;
    }

    function _mintWrappedDerivativeTokens(address recipient_, uint256 amount_) internal {
        // Mint underlying tokens for transfer
        _underlyingToken.mint(address(_auctionHouse), amount_);

        // Approve spending of underlying tokens (which is done in the AuctionHouse)
        vm.prank(address(_auctionHouse));
        _underlyingToken.approve(address(_linearVesting), amount_);

        // Mint wrapped derivative tokens
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(recipient_, _underlyingTokenAddress, _vestingParamsBytes, amount_, true);
    }

    modifier givenAliceHasWrappedDerivativeTokens(uint256 amount_) {
        _mintWrappedDerivativeTokens(_ALICE, amount_);
        _;
    }

    modifier givenUnderlyingTokenIsFeeOnTransfer() {
        _underlyingToken.setTransferFee(100);
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
        _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);
    }

    function test_deploy_underlyingTokenIsZero_reverts() public whenUnderlyingTokenIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);
    }

    function test_deploy_startTimestampIsZero_reverts() public whenStartTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);
    }

    function test_deploy_expiryTimestampIsZero_reverts() public whenExpiryTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);
    }

    function test_deploy_startAndExpiryTimestampsAreTheSame_reverts()
        public
        whenStartAndExpiryTimestampsAreTheSame
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);
    }

    function test_deploy_startTimestampIsAfterExpiryTimestamp_reverts()
        public
        whenStartTimestampIsAfterExpiryTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);
    }

    function test_deploy_startTimestampIsBeforeCurrentTimestamp()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

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
        _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);
    }

    function test_deploy_wrapped_derivativeDeployed_wrappedDerivativeDeployed()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "derivative token id");
        assertEq(wrappedAddress, _derivativeWrappedAddress, "derivative wrapped address");

        // Check token metadata
        Derivative.Token memory tokenMetadata = _linearVesting.getTokenMetadata(tokenId);
        assertEq(tokenMetadata.exists, true, "tokenMetadata exists");
        assertEq(tokenMetadata.wrapped, wrappedAddress, "tokenMetadata wrapped");
        assertEq(
            tokenMetadata.underlyingToken, _underlyingTokenAddress, "tokenMetadata underlying token"
        );
        assertEq(tokenMetadata.data.length, _VESTING_DATA_LEN, "tokenMetadata data length");

        // Check implementation data
        LinearVesting.VestingData memory vestingData =
            abi.decode(tokenMetadata.data, (LinearVesting.VestingData));
        assertEq(vestingData.start, _VESTING_START, "vesting start");
        assertEq(vestingData.expiry, _VESTING_EXPIRY, "vesting expiry");
        assertEq(address(vestingData.baseToken), _underlyingTokenAddress, "vesting base token");
    }

    function test_deploy_wrapped_derivativeDeployed_wrappedDerivativeNotDeployed()
        public
        givenDerivativeIsDeployed
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "derivative token id");
        assertTrue(wrappedAddress != address(0), "derivative wrapped address");

        // Check token metadata
        Derivative.Token memory tokenMetadata = _linearVesting.getTokenMetadata(tokenId);
        assertEq(tokenMetadata.exists, true, "tokenMetadata exists");
        assertEq(tokenMetadata.wrapped, wrappedAddress, "tokenMetadata wrapped");
        assertEq(
            tokenMetadata.underlyingToken, _underlyingTokenAddress, "tokenMetadata underlying token"
        );
        assertEq(tokenMetadata.data.length, _VESTING_DATA_LEN, "tokenMetadata data length");

        // Check implementation data
        LinearVesting.VestingData memory vestingData =
            abi.decode(tokenMetadata.data, (LinearVesting.VestingData));
        assertEq(vestingData.start, _VESTING_START, "vesting start");
        assertEq(vestingData.expiry, _VESTING_EXPIRY, "vesting expiry");
        assertEq(address(vestingData.baseToken), _underlyingTokenAddress, "vesting base token");
    }

    function test_deploy_wrapped() public {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

        // Check values
        assertTrue(tokenId > 0, "derivative token id");
        assertTrue(wrappedAddress != address(0), "derivative wrapped address");

        // Check wrapped token
        SoulboundCloneERC20 wrappedDerivative = SoulboundCloneERC20(wrappedAddress);
        assertEq(
            wrappedDerivative.name().trim(0, _wrappedDerivativeTokenNameLength),
            _wrappedDerivativeTokenName,
            "wrapped derivative name"
        );
        assertEq(
            wrappedDerivative.symbol().trim(0, _wrappedDerivativeTokenSymbolLength),
            _wrappedDerivativeTokenSymbol,
            "wrapped derivative symbol"
        );
        assertEq(wrappedDerivative.decimals(), 18, "wrapped derivative decimals");
        assertEq(
            address(wrappedDerivative.underlying()),
            _underlyingTokenAddress,
            "wrapped derivative underlying address"
        );
        assertEq(wrappedDerivative.expiry(), _VESTING_EXPIRY, "wrapped derivative expiry");
        assertEq(wrappedDerivative.owner(), address(_linearVesting), "wrapped derivative owner");

        // Check token metadata
        Derivative.Token memory tokenMetadata = _linearVesting.getTokenMetadata(tokenId);
        assertEq(tokenMetadata.exists, true, "tokenMetadata exists");
        assertEq(tokenMetadata.wrapped, wrappedAddress, "tokenMetadata wrapped");
        assertEq(
            tokenMetadata.underlyingToken, _underlyingTokenAddress, "tokenMetadata underlying token"
        );
        assertEq(tokenMetadata.data.length, _VESTING_DATA_LEN, "tokenMetadata data length");

        // Check implementation data
        LinearVesting.VestingData memory vestingData =
            abi.decode(tokenMetadata.data, (LinearVesting.VestingData));
        assertEq(vestingData.start, _VESTING_START, "vesting start");
        assertEq(vestingData.expiry, _VESTING_EXPIRY, "vesting expiry");
        assertEq(address(vestingData.baseToken), _underlyingTokenAddress, "vesting base token");
    }

    function test_deploy_notWrapped() public {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, false);

        // Check values
        assertTrue(tokenId > 0, "derivative token id");
        assertTrue(wrappedAddress == address(0), "wrapped address");

        // Check token metadata
        Derivative.Token memory tokenMetadata = _linearVesting.getTokenMetadata(tokenId);
        assertEq(tokenMetadata.exists, true, "tokenMetadata exists");
        assertEq(tokenMetadata.wrapped, address(0), "tokenMetadata wrapped address");
        assertEq(
            tokenMetadata.underlyingToken, _underlyingTokenAddress, "tokenMetadata underlying token"
        );
        assertEq(tokenMetadata.data.length, _VESTING_DATA_LEN, "tokenMetadata data length");

        // Check implementation data
        LinearVesting.VestingData memory vestingData =
            abi.decode(tokenMetadata.data, (LinearVesting.VestingData));
        assertEq(vestingData.start, _VESTING_START, "vesting start");
        assertEq(vestingData.expiry, _VESTING_EXPIRY, "vesting expiry");
        assertEq(address(vestingData.baseToken), _underlyingTokenAddress, "vesting base token");
    }

    function test_deploy_notParent() public {
        // Call
        vm.prank(_ALICE);
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

        // Check values
        assertTrue(tokenId > 0, "derivative token id");
        assertTrue(wrappedAddress != address(0), "derivative wrapped address");

        // Check wrapped token
        SoulboundCloneERC20 wrappedDerivative = SoulboundCloneERC20(wrappedAddress);
        assertEq(
            wrappedDerivative.name().trim(0, _wrappedDerivativeTokenNameLength),
            _wrappedDerivativeTokenName,
            "wrapped derivative name"
        );
        assertEq(
            wrappedDerivative.symbol().trim(0, _wrappedDerivativeTokenSymbolLength),
            _wrappedDerivativeTokenSymbol,
            "wrapped derivative symbol"
        );
        assertEq(wrappedDerivative.decimals(), 18, "wrapped derivative decimals");
        assertEq(
            address(wrappedDerivative.underlying()),
            _underlyingTokenAddress,
            "wrapped derivative underlying address"
        );
        assertEq(wrappedDerivative.expiry(), _vestingParams.expiry);
        assertEq(wrappedDerivative.owner(), address(_linearVesting), "wrapped derivative owner");
    }

    function test_deploy_notParent_derivativeDeployed_wrappedDerivativeDeployed()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(_ALICE);
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "derivative token id");
        assertEq(wrappedAddress, _derivativeWrappedAddress, "derivative wrapped address");
    }

    function test_deploy_differentVestingParams()
        public
        givenWrappedDerivativeIsDeployed
        whenVestingParamsAreChanged
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

        // Check values
        assertFalse(tokenId == _derivativeTokenId, "derivative token id");
        assertFalse(wrappedAddress == _derivativeWrappedAddress, "derivative wrapped address");

        // Check wrapped token
        SoulboundCloneERC20 wrappedDerivative = SoulboundCloneERC20(wrappedAddress);
        assertEq(
            wrappedDerivative.name().trim(0, _wrappedDerivativeTokenNameLength),
            _wrappedDerivativeTokenName,
            "wrapped derivative name"
        );
        assertEq(
            wrappedDerivative.symbol().trim(0, _wrappedDerivativeTokenSymbolLength),
            _wrappedDerivativeTokenSymbol,
            "wrapped derivative symbol"
        );
        assertEq(wrappedDerivative.decimals(), 18, "wrapped derivative decimals");
        assertEq(
            address(wrappedDerivative.underlying()),
            _underlyingTokenAddress,
            "wrapped derivative underlying address"
        );
        assertEq(wrappedDerivative.expiry(), _vestingParams.expiry);
        assertEq(wrappedDerivative.owner(), address(_linearVesting), "wrapped derivative owner");
    }

    function test_deploy_differentUnderlyingToken()
        public
        givenWrappedDerivativeIsDeployed
        whenUnderlyingTokenIsChanged
    {
        // Call
        (uint256 tokenId, address wrappedAddress) =
            _linearVesting.deploy(_underlyingTokenAddress, _vestingParamsBytes, true);

        // Check values
        assertFalse(tokenId == _derivativeTokenId, "derivative token id");
        assertFalse(wrappedAddress == _derivativeWrappedAddress, "derivative wrapped address");

        // Check wrapped token
        SoulboundCloneERC20 wrappedDerivative = SoulboundCloneERC20(wrappedAddress);
        assertEq(
            wrappedDerivative.name().trim(0, _wrappedDerivativeTokenNameLength),
            _wrappedDerivativeTokenName,
            "wrapped derivative name"
        );
        assertEq(
            wrappedDerivative.symbol().trim(0, _wrappedDerivativeTokenSymbolLength),
            _wrappedDerivativeTokenSymbol,
            "wrapped derivative symbol"
        );
        assertEq(wrappedDerivative.decimals(), 17);
        assertEq(
            address(wrappedDerivative.underlying()),
            _underlyingTokenAddress,
            "wrapped derivative underlying address"
        );
        assertEq(wrappedDerivative.expiry(), _vestingParams.expiry);
        assertEq(wrappedDerivative.owner(), address(_linearVesting), "wrapped derivative owner");
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
        _linearVesting.validate(_underlyingTokenAddress, _vestingParamsBytes);
    }

    function test_validate_startTimestampIsZero() public whenStartTimestampIsZero {
        // Call
        bool isValid = _linearVesting.validate(_underlyingTokenAddress, _vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_expiryTimestampIsZero() public whenExpiryTimestampIsZero {
        // Call
        bool isValid = _linearVesting.validate(_underlyingTokenAddress, _vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startAndExpiryTimestampsAreTheSame()
        public
        whenStartAndExpiryTimestampsAreTheSame
    {
        // Call
        bool isValid = _linearVesting.validate(_underlyingTokenAddress, _vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startTimestampIsAfterExpiryTimestamp()
        public
        whenStartTimestampIsAfterExpiryTimestamp
    {
        // Call
        bool isValid = _linearVesting.validate(_underlyingTokenAddress, _vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate_startTimestampIsBeforeCurrentTimestamp()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
    {
        // Call
        bool isValid = _linearVesting.validate(_underlyingTokenAddress, _vestingParamsBytes);

        // Check values
        assertTrue(isValid);
    }

    function test_validate_expiryTimestampIsBeforeCurrentTimestamp()
        public
        whenExpiryTimestampIsBeforeCurrentTimestamp
    {
        // Call
        bool isValid = _linearVesting.validate(_underlyingTokenAddress, _vestingParamsBytes);

        // Check values
        assertFalse(isValid);
    }

    function test_validate() public {
        // Call
        bool isValid = _linearVesting.validate(_underlyingTokenAddress, _vestingParamsBytes);

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
        _linearVesting.computeId(_underlyingTokenAddress, _vestingParamsBytes);
    }

    function test_computeId_paramsChanged()
        public
        givenDerivativeIsDeployed
        whenVestingParamsAreChanged
    {
        // Call
        uint256 tokenId = _linearVesting.computeId(_underlyingTokenAddress, _vestingParamsBytes);

        // Check values
        assertFalse(tokenId == _derivativeTokenId, "derivative token id");
    }

    function test_computeId() public givenDerivativeIsDeployed {
        // Call
        uint256 tokenId = _linearVesting.computeId(_underlyingTokenAddress, _vestingParamsBytes);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "derivative token id");
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
    // [X] given the underlying token is fee-on-transfer
    //  [X] it reverts
    // [X] given it is before the vesting start
    //  [X] it mints the derivative tokens and returns a redeemable amount of 0
    // [X] given it is after the vesting start
    //  [X] it mints the derivative tokens and returns the correct redeemable amount
    // [X] given the user has existing minted tokens
    //  [X] it mints the additional derivative tokens and returns the correct redeemable amount
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
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_underlyingTokenIsZero_reverts() public whenUnderlyingTokenIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_startTimestampIsZero_reverts() public whenStartTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_expiryTimestampIsZero_reverts() public whenExpiryTimestampIsZero {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_startAndExpiryTimestampsAreTheSame_reverts()
        public
        whenStartAndExpiryTimestampsAreTheSame
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_startTimestampIsAfterExpiryTimestamp_reverts()
        public
        whenStartTimestampIsAfterExpiryTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_startTimestampIsBeforeCurrentTimestamp()
        public
        whenStartTimestampIsBeforeCurrentTimestamp
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) = _linearVesting.mint(
            _ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false
        );

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), _AMOUNT, "balanceOf mismatch");
    }

    function test_mint_params_expiryTimestampIsBeforeCurrentTimestamp_reverts()
        public
        whenExpiryTimestampIsBeforeCurrentTimestamp
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
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
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_mintAmountIsZero_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, 0, false);
    }

    function test_mint_params_recipientIsZero()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId,,) = _linearVesting.mint(
            address(0), _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false
        );

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertEq(_linearVesting.balanceOf(address(0), tokenId), _AMOUNT, "balanceOf mismatch");
    }

    function test_mint_params_insufficentBalance_reverts() public {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_feeOnTransfer_reverts()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenUnderlyingTokenIsFeeOnTransfer
        givenDerivativeIsDeployed
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LinearVesting.UnsupportedToken.selector, _underlyingTokenAddress);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
    }

    function test_mint_params_beforeVestingStart()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenBeforeVestingStart
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) = _linearVesting.mint(
            _ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false
        );

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(
            _linearVesting.balanceOf(_ALICE, tokenId), _AMOUNT, "derivative: balanceOf mismatch"
        );
        assertEq(_underlyingToken.balanceOf(_ALICE), 0, "underlying: balanceOf mismatch");
        assertEq(_linearVesting.redeemable(_ALICE, tokenId), 0, "redeemable mismatch");
    }

    function test_mint_params_afterVestingStart(uint48 elapsed_)
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
    {
        uint48 elapsed = uint48(bound(elapsed_, 1, _VESTING_DURATION));
        vm.warp(_VESTING_START + elapsed);

        // Calculate the amount that should be redeemed
        uint256 expectedRedeemableAmount = _AMOUNT * elapsed / _VESTING_DURATION;

        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) = _linearVesting.mint(
            _ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false
        );

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(
            _linearVesting.balanceOf(_ALICE, tokenId), _AMOUNT, "derivative: balanceOf mismatch"
        );
        assertEq(_underlyingToken.balanceOf(_ALICE), 0, "underlying: balanceOf mismatch");
        assertEq(
            _linearVesting.redeemable(_ALICE, tokenId),
            expectedRedeemableAmount,
            "redeemable mismatch"
        );
    }

    function test_mint_params_givenExistingDerivativeTokens_afterVestingStart(uint48 elapsed_)
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT + _AMOUNT_TWO)
    {
        uint48 elapsedOne = uint48(10_000);
        uint48 elapsedTwo = uint48(bound(elapsed_, elapsedOne + 1, _VESTING_DURATION));

        // Warp to the first checkpoint
        vm.warp(_VESTING_START + elapsedOne);

        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId,,) = _linearVesting.mint(
            _ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false
        );

        // Warp to the second checkpoint
        vm.warp(_VESTING_START + elapsedTwo);

        // Calculate amounts
        uint256 expectedRedeemableAmount = (_AMOUNT + _AMOUNT_TWO) * elapsedTwo / _VESTING_DURATION;

        // Mint more tokens
        vm.prank(address(_auctionHouse));
        (uint256 tokenIdTwo, address wrappedAddressTwo, uint256 amountCreatedTwo) = _linearVesting
            .mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT_TWO, false);

        // Check values
        assertEq(tokenId, tokenIdTwo, "tokenId mismatch");
        assertTrue(wrappedAddressTwo == address(0), "wrappedAddress mismatch");
        assertEq(amountCreatedTwo, _AMOUNT_TWO, "amountCreated mismatch");
        assertEq(
            _linearVesting.balanceOf(_ALICE, tokenId),
            _AMOUNT + _AMOUNT_TWO,
            "derivative: balanceOf mismatch"
        );
        assertEq(_underlyingToken.balanceOf(_ALICE), 0, "underlying: balanceOf mismatch");
        assertEq(
            _linearVesting.redeemable(_ALICE, tokenId),
            expectedRedeemableAmount,
            "redeemable mismatch"
        );
    }

    function test_mint_params_notWrapped_tokenNotDeployed()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) = _linearVesting.mint(
            _ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false
        );

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), _AMOUNT, "balanceOf mismatch");
    }

    function test_mint_params_notWrapped_tokenDeployed()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) = _linearVesting.mint(
            _ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false
        );

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), _AMOUNT, "balanceOf mismatch");
    }

    function test_mint_params_wrapped_wrappedTokenIsNotDeployed()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, true);

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress != address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_ALICE), _AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_params_wrapped_wrappedTokenIsDeployed()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, true);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "tokenId mismatch");
        assertEq(wrappedAddress, _derivativeWrappedAddress, "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_ALICE), _AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_params_notParent()
        public
        givenCallerHasUnderlyingTokenBalance(_ALICE, _AMOUNT)
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(_ALICE);
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, true);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "tokenId mismatch");
        assertEq(wrappedAddress, _derivativeWrappedAddress, "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_ALICE), _AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_params_notParent_insufficientBalance_reverts()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call
        vm.prank(_ALICE);
        _linearVesting.mint(_ALICE, _underlyingTokenAddress, _vestingParamsBytes, _AMOUNT, false);
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
    // [X] given it is before the vesting start
    //  [X] it mints the derivative tokens and returns a redeemable amount of 0
    // [X] given it is after the vesting start
    //  [X] it mints the derivative tokens and returns the correct redeemable amount
    // [X] given the user has existing minted tokens
    //  [X] it mints the additional derivative tokens and returns the correct redeemable amount
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
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, false);
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
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, false);
    }

    function test_mint_tokenId_whenMintAmountIsZero_reverts() public givenDerivativeIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _derivativeTokenId, 0, false);
    }

    function test_mint_tokenId_whenRecipientIsZero()
        public
        givenDerivativeIsDeployed
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId,,) = _linearVesting.mint(address(0), _derivativeTokenId, _AMOUNT, false);

        // Check values
        assertEq(_linearVesting.balanceOf(address(0), tokenId), _AMOUNT);
    }

    function test_mint_tokenId_insufficentBalance_reverts() public givenDerivativeIsDeployed {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, false);
    }

    function test_mint_tokenId_feeOnTransfer_reverts()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenUnderlyingTokenIsFeeOnTransfer
        givenDerivativeIsDeployed
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(LinearVesting.UnsupportedToken.selector, _underlyingTokenAddress);
        vm.expectRevert(err);

        // Call
        vm.prank(address(_auctionHouse));
        _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, false);
    }

    function test_mint_tokenId_beforeVestingStart()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenBeforeVestingStart
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, false);

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(
            _linearVesting.balanceOf(_ALICE, tokenId), _AMOUNT, "derivative: balanceOf mismatch"
        );
        assertEq(_underlyingToken.balanceOf(_ALICE), 0, "underlying: balanceOf mismatch");
        assertEq(_linearVesting.redeemable(_ALICE, tokenId), 0, "redeemable mismatch");
    }

    function test_mint_tokenId_afterVestingStart(uint48 elapsed_)
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenDerivativeIsDeployed
    {
        uint48 elapsed = uint48(bound(elapsed_, 1, _VESTING_DURATION));
        vm.warp(_VESTING_START + elapsed);

        // Calculate the amount that should be redeemed
        uint256 expectedRedeemableAmount = _AMOUNT * elapsed / _VESTING_DURATION;

        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, false);

        // Check values
        assertTrue(tokenId > 0, "tokenId mismatch");
        assertTrue(wrappedAddress == address(0), "wrappedAddress mismatch");
        assertEq(amountCreated, _AMOUNT, "amountCreated mismatch");
        assertEq(
            _linearVesting.balanceOf(_ALICE, tokenId), _AMOUNT, "derivative: balanceOf mismatch"
        );
        assertEq(_underlyingToken.balanceOf(_ALICE), 0, "underlying: balanceOf mismatch");
        assertEq(
            _linearVesting.redeemable(_ALICE, tokenId),
            expectedRedeemableAmount,
            "redeemable mismatch"
        );
    }

    function test_mint_tokenId_givenExistingDerivativeTokens_afterVestingStart(uint48 elapsed_)
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT + _AMOUNT_TWO)
        givenDerivativeIsDeployed
    {
        uint48 elapsedOne = uint48(10_000);
        uint48 elapsedTwo = uint48(bound(elapsed_, elapsedOne + 1, _VESTING_DURATION));

        // Warp to the first checkpoint
        vm.warp(_VESTING_START + elapsedOne);

        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId,,) = _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, false);

        // Warp to the second checkpoint
        vm.warp(_VESTING_START + elapsedTwo);

        // Calculate amounts
        uint256 expectedRedeemableAmount = (_AMOUNT + _AMOUNT_TWO) * elapsedTwo / _VESTING_DURATION;

        // Mint more tokens
        vm.prank(address(_auctionHouse));
        (uint256 tokenIdTwo, address wrappedAddressTwo, uint256 amountCreatedTwo) =
            _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT_TWO, false);

        // Check values
        assertEq(tokenId, tokenIdTwo, "tokenId mismatch");
        assertTrue(wrappedAddressTwo == address(0), "wrappedAddress mismatch");
        assertEq(amountCreatedTwo, _AMOUNT_TWO, "amountCreated mismatch");
        assertEq(
            _linearVesting.balanceOf(_ALICE, tokenId),
            _AMOUNT + _AMOUNT_TWO,
            "derivative: balanceOf mismatch"
        );
        assertEq(_underlyingToken.balanceOf(_ALICE), 0, "underlying: balanceOf mismatch");
        assertEq(
            _linearVesting.redeemable(_ALICE, tokenId),
            expectedRedeemableAmount,
            "redeemable mismatch"
        );
    }

    function test_mint_tokenId_notWrapped()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, false);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "derivative token id");
        assertTrue(wrappedAddress == address(0));
        assertEq(amountCreated, _AMOUNT);
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), _AMOUNT, "balanceOf mismatch");
    }

    function test_mint_tokenId_wrapped_wrappedTokenIsNotDeployed()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenDerivativeIsDeployed
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, true);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "derivative token id");
        assertTrue(wrappedAddress != address(0), "derivative wrapped address");
        assertEq(amountCreated, _AMOUNT);
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_ALICE), _AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_tokenId_wrapped_wrappedTokenIsDeployed()
        public
        givenParentHasUnderlyingTokenBalance(_AMOUNT)
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(address(_auctionHouse));
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, true);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "derivative token id");
        assertEq(wrappedAddress, _derivativeWrappedAddress, "derivative wrapped address");
        assertEq(amountCreated, _AMOUNT);
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_ALICE), _AMOUNT, "balanceOf mismatch"
        );
    }

    function test_mint_tokenId_notParent()
        public
        givenCallerHasUnderlyingTokenBalance(_ALICE, _AMOUNT)
        givenWrappedDerivativeIsDeployed
    {
        // Call
        vm.prank(_ALICE);
        (uint256 tokenId, address wrappedAddress, uint256 amountCreated) =
            _linearVesting.mint(_ALICE, _derivativeTokenId, _AMOUNT, true);

        // Check values
        assertEq(tokenId, _derivativeTokenId, "derivative token id");
        assertEq(wrappedAddress, _derivativeWrappedAddress, "derivative wrapped address");
        assertEq(amountCreated, _AMOUNT);
        assertEq(_linearVesting.balanceOf(_ALICE, tokenId), 0, "balanceOf mismatch");
        assertEq(
            SoulboundCloneERC20(wrappedAddress).balanceOf(_ALICE), _AMOUNT, "balanceOf mismatch"
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
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, _AMOUNT);
    }

    function test_redeem_givenRedeemAmountIsZero_reverts() public givenDerivativeIsDeployed {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, 0);
    }

    function test_redeem_givenAmountGreaterThanRedeemable_reverts(uint48 elapsed_)
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
    {
        // Warp to mid-way, so not all tokens are vested
        uint48 elapsed = uint48(bound(elapsed_, 1, _VESTING_DURATION - 1));
        vm.warp(_VESTING_START + elapsed);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, _AMOUNT);
    }

    function test_redeem_insufficientBalance_reverts()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.redeem(_derivativeTokenId, _AMOUNT);
    }

    function test_redeem_givenWrappedTokenNotDeployed(uint256 amount_)
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amount = bound(amount_, 1, _AMOUNT);

        // Call
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, amount);

        // Check values
        assertEq(_linearVesting.balanceOf(_ALICE, _derivativeTokenId), _AMOUNT - amount);
        assertEq(SoulboundCloneERC20(_underlyingTokenAddress).balanceOf(_ALICE), amount);
    }

    function test_redeem_givenWrappedBalance(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(_AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amount = bound(amount_, 1, _AMOUNT);

        // Call
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, amount);

        // Check values
        assertEq(_linearVesting.balanceOf(_ALICE, _derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE), _AMOUNT - amount);
        assertEq(SoulboundCloneERC20(_underlyingTokenAddress).balanceOf(_ALICE), amount);
    }

    function test_redeem_givenUnwrappedBalance(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amount = bound(amount_, 1, _AMOUNT);

        // Call
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, amount);

        // Check values
        assertEq(_linearVesting.balanceOf(_ALICE, _derivativeTokenId), _AMOUNT - amount);
        assertEq(SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE), 0);
        assertEq(SoulboundCloneERC20(_underlyingTokenAddress).balanceOf(_ALICE), amount);
    }

    function test_redeem_givenMixedBalance()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenAliceHasWrappedDerivativeTokens(_AMOUNT)
        givenAfterVestingExpiry
    {
        uint256 amountToRedeem = _AMOUNT + 1;

        // Call
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, amountToRedeem);

        // Check values
        assertEq(_linearVesting.balanceOf(_ALICE, _derivativeTokenId), 0); // Redeems unwrapped first
        assertEq(SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE), _AMOUNT - 1);
        assertEq(SoulboundCloneERC20(_underlyingTokenAddress).balanceOf(_ALICE), amountToRedeem);
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
        vm.prank(_ALICE);
        _linearVesting.redeemMax(_derivativeTokenId);
    }

    function test_redeemMax_givenRedeemableAmountIsZero_reverts()
        public
        givenDerivativeIsDeployed
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InsufficientBalance.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.redeemMax(_derivativeTokenId);
    }

    function test_redeemMax_givenWrappedTokenNotDeployed()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        vm.prank(_ALICE);
        _linearVesting.redeemMax(_derivativeTokenId);

        // Check values
        assertEq(_linearVesting.balanceOf(_ALICE, _derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(_underlyingTokenAddress).balanceOf(_ALICE), _AMOUNT);
    }

    function test_redeemMax_givenWrappedBalance_givenVestingExpiry()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(_AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        vm.prank(_ALICE);
        _linearVesting.redeemMax(_derivativeTokenId);

        // Check values
        assertEq(_linearVesting.balanceOf(_ALICE, _derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE), 0);
        assertEq(SoulboundCloneERC20(_underlyingTokenAddress).balanceOf(_ALICE), _AMOUNT);
    }

    function test_redeemMax_givenUnwrappedBalance_givenVestingExpiry()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        vm.prank(_ALICE);
        _linearVesting.redeemMax(_derivativeTokenId);

        // Check values
        assertEq(_linearVesting.balanceOf(_ALICE, _derivativeTokenId), 0);
        assertEq(SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE), 0);
        assertEq(SoulboundCloneERC20(_underlyingTokenAddress).balanceOf(_ALICE), _AMOUNT);
    }

    function test_redeemMax(uint48 elapsed_) public givenWrappedDerivativeIsDeployed {
        // Mint both wrapped and unwrapped
        _mintDerivativeTokens(_ALICE, _AMOUNT);
        _mintWrappedDerivativeTokens(_ALICE, _AMOUNT);

        // Warp during vesting
        uint48 elapsed = uint48(bound(elapsed_, 1, _VESTING_DURATION - 1));
        vm.warp(_VESTING_START + elapsed);

        uint256 redeemable = (_AMOUNT + _AMOUNT) * elapsed / _VESTING_DURATION;
        uint256 expectedBalanceUnwrapped;
        uint256 expectedBalanceWrapped;
        if (redeemable < _AMOUNT) {
            expectedBalanceUnwrapped = _AMOUNT - redeemable;
            expectedBalanceWrapped = _AMOUNT;
        } else {
            expectedBalanceUnwrapped = 0;
            expectedBalanceWrapped = _AMOUNT - (redeemable - _AMOUNT);
        }

        // Call
        vm.prank(_ALICE);
        _linearVesting.redeemMax(_derivativeTokenId);

        // Check values
        assertEq(
            _linearVesting.balanceOf(_ALICE, _derivativeTokenId),
            expectedBalanceUnwrapped,
            "derivative token: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE),
            expectedBalanceWrapped,
            "wrapped derivative token: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(_underlyingTokenAddress).balanceOf(_ALICE),
            redeemable,
            "underlying token: balanceOf mismatch"
        );
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
        _linearVesting.redeemable(_ALICE, _derivativeTokenId);
    }

    function test_redeemable_givenBeforeStart_returnsZero()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenBeforeVestingStart
    {
        // Call
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, 0);
    }

    function test_redeemable_givenAfterExpiry()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenAfterVestingExpiry
    {
        // Call
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, _AMOUNT);
    }

    function test_redeemable_givenWrappedTokenNotDeployed()
        public
        givenDerivativeIsDeployed
        givenAfterVestingExpiry
    {
        // Call
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, 0);
    }

    function test_redeemable_givenBeforeExpiry(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
    {
        uint256 amount = bound(amount_, 1, _AMOUNT);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_ALICE, amount);

        // Warp to before expiry
        uint48 elapsed = 100_000;
        vm.warp(_VESTING_START + elapsed);

        // Includes wrapped and unwrapped balances
        uint256 expectedRedeemable = elapsed * (_AMOUNT + amount) / _VESTING_DURATION;

        // Call
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable);
    }

    function test_redeemable_givenRedemption(
        uint256 wrappedAmount_,
        uint256 unwrappedAmount_,
        uint256 redeemPercentage_
    ) public givenWrappedDerivativeIsDeployed {
        uint256 wrappedAmount = bound(wrappedAmount_, 1e9, _AMOUNT);
        uint256 unwrappedAmount = bound(unwrappedAmount_, 1e9, _AMOUNT);
        uint256 redeemPercentage = bound(redeemPercentage_, 1, 100);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_ALICE, wrappedAmount);

        // Mint derivative tokens
        _mintDerivativeTokens(_ALICE, unwrappedAmount);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(_VESTING_START + elapsed);

        // Calculate redeemable amount
        uint256 redeemable = elapsed * (wrappedAmount + unwrappedAmount) / _VESTING_DURATION;
        uint256 amountToRedeem = redeemable * redeemPercentage / 100;

        // Redeem
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, amountToRedeem);

        // Call
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, redeemable - amountToRedeem, "redeemable mismatch");
    }

    function test_redeemable_redemptions() public givenWrappedDerivativeIsDeployed {
        // Mint tokens
        _mintDerivativeTokens(_ALICE, _AMOUNT);
        _mintWrappedDerivativeTokens(_ALICE, _AMOUNT);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(_VESTING_START + elapsed);

        // Calculate the vested amount
        uint256 vestedAmount = (elapsed * (_AMOUNT + _AMOUNT)) / _VESTING_DURATION;
        uint256 claimedAmount = 0;
        uint256 redeemableAmount = vestedAmount - claimedAmount;

        assertEq(
            _linearVesting.redeemable(_ALICE, _derivativeTokenId),
            redeemableAmount,
            "1: redeemable mismatch"
        );

        // Redeem half the tokens
        uint256 redeemAmount = redeemableAmount / 2;
        claimedAmount += redeemAmount;
        redeemableAmount = vestedAmount - claimedAmount;

        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, redeemAmount);

        assertEq(
            _linearVesting.redeemable(_ALICE, _derivativeTokenId),
            redeemableAmount,
            "2: redeemable mismatch"
        );

        // Redeem the remaining tokens
        redeemAmount = redeemableAmount;
        claimedAmount += redeemAmount;
        redeemableAmount = 0;

        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, redeemAmount);

        assertEq(
            _linearVesting.redeemable(_ALICE, _derivativeTokenId),
            redeemableAmount,
            "3: redeemable mismatch"
        );

        // Check that the claimed amount is the same as the vested amount
        assertEq(claimedAmount, vestedAmount, "claimedAmount mismatch");

        // Warp to another time
        elapsed = 60_000;
        vm.warp(_VESTING_START + elapsed);

        // Calculate the vested amount
        vestedAmount = elapsed * (_AMOUNT + _AMOUNT) / _VESTING_DURATION;
        redeemableAmount = vestedAmount - claimedAmount;

        assertEq(
            _linearVesting.redeemable(_ALICE, _derivativeTokenId),
            redeemableAmount,
            "4: redeemable mismatch"
        );

        // Redeem half the tokens
        redeemAmount = redeemableAmount / 2;
        claimedAmount += redeemAmount;
        redeemableAmount = vestedAmount - claimedAmount;

        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, redeemAmount);

        assertEq(
            _linearVesting.redeemable(_ALICE, _derivativeTokenId),
            redeemableAmount,
            "5: redeemable mismatch"
        );

        // Redeem the remaining tokens
        redeemAmount = redeemableAmount;
        claimedAmount += redeemAmount;
        redeemableAmount = 0;

        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, redeemAmount);

        assertEq(
            _linearVesting.redeemable(_ALICE, _derivativeTokenId),
            redeemableAmount,
            "6: redeemable mismatch"
        );

        // Check that the claimed amount is the same as the vested amount
        assertEq(claimedAmount, vestedAmount, "claimedAmount mismatch");
    }

    function test_redeemable_givenTokensMintedAfterDeployment(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(_AMOUNT)
    {
        uint256 amount = bound(amount_, 1e9, _AMOUNT);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(_VESTING_START + elapsed);

        // Mint tokens
        _mintDerivativeTokens(_ALICE, amount);

        uint256 expectedRedeemable = (_AMOUNT + amount) * elapsed / _VESTING_DURATION;

        // Call
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable, "redeemable mismatch");
    }

    function test_redeemable_givenWrappedTokensMintedAfterDeployment(uint256 amount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
    {
        uint256 amount = bound(amount_, 1e9, _AMOUNT);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(_VESTING_START + elapsed);

        // Mint tokens
        _mintWrappedDerivativeTokens(_ALICE, amount);

        uint256 expectedRedeemable = (_AMOUNT + amount) * elapsed / _VESTING_DURATION;

        // Call
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, expectedRedeemable, "redeemable mismatch");
    }

    function test_redeemable_givenRedemption_givenTokensMintedAfterDeployment(
        uint256 wrappedAmount_,
        uint256 unwrappedAmount_,
        uint256 redeemPercentage_
    ) public givenWrappedDerivativeIsDeployed {
        uint256 wrappedAmount = bound(wrappedAmount_, 1e9, _AMOUNT);
        uint256 unwrappedAmount = bound(unwrappedAmount_, 1e9, _AMOUNT);
        uint256 redeemPercentage = bound(redeemPercentage_, 1, 100);

        // Mint wrapped derivative tokens
        _mintWrappedDerivativeTokens(_ALICE, wrappedAmount);

        // Mint derivative tokens
        _mintDerivativeTokens(_ALICE, unwrappedAmount);

        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(_VESTING_START + elapsed);

        // Redeem wrapped tokens
        uint256 redeemable = elapsed * (wrappedAmount + unwrappedAmount) / _VESTING_DURATION;
        uint256 amountToRedeem = redeemable * redeemPercentage / 100;

        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, amountToRedeem);

        // Mint more tokens
        _mintDerivativeTokens(_ALICE, _AMOUNT);
        _mintWrappedDerivativeTokens(_ALICE, _AMOUNT);

        // Warp to another time
        elapsed = 60_000;
        vm.warp(_VESTING_START + elapsed);

        // Calculate the vested amount
        uint256 vestedAmount =
            elapsed * (_AMOUNT + _AMOUNT + unwrappedAmount + wrappedAmount) / _VESTING_DURATION;
        uint256 claimedAmount = amountToRedeem;
        uint256 expectedRedeemableAmount = vestedAmount - claimedAmount;

        // Call
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");
    }

    function test_redeemable_givenRedemption_givenUnwrapped()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenAliceHasWrappedDerivativeTokens(_AMOUNT)
    {
        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(_VESTING_START + elapsed);

        uint256 vested = (_AMOUNT + _AMOUNT).mulDivDown(elapsed, _VESTING_DURATION);

        // Redeem tokens - partial amount
        uint256 redeemAmount = 1e9;
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, redeemAmount);

        // Unwrap half of the remaining wrapped tokens
        uint256 wrappedToUnwrap =
            SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE) / 2;
        vm.prank(_ALICE);
        _linearVesting.unwrap(_derivativeTokenId, wrappedToUnwrap);

        uint256 expectedRedeemableAmount = vested - redeemAmount;

        // Check the redeemable amount
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");

        // Warp to another time
        elapsed = 60_000;
        vm.warp(_VESTING_START + elapsed);

        vested = (_AMOUNT + _AMOUNT).mulDivDown(elapsed, _VESTING_DURATION);
        expectedRedeemableAmount = vested - redeemAmount;

        // Check the redeemable amount
        redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");
    }

    function test_redeemable_givenRedemption_givenWrapped()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
        givenAliceHasWrappedDerivativeTokens(_AMOUNT)
    {
        // Warp to before expiry
        uint48 elapsed = 50_000;
        vm.warp(_VESTING_START + elapsed);

        uint256 vested = (_AMOUNT + _AMOUNT).mulDivDown(elapsed, _VESTING_DURATION);

        // Redeem tokens - partial amount
        uint256 redeemAmount = vested / 4;
        vm.prank(_ALICE);
        _linearVesting.redeem(_derivativeTokenId, redeemAmount);

        // Wrap half of the remaining unwrapped tokens
        uint256 unwrappedToWrap = _linearVesting.balanceOf(_ALICE, _derivativeTokenId) / 2;
        vm.prank(_ALICE);
        _linearVesting.wrap(_derivativeTokenId, unwrappedToWrap);

        uint256 expectedRedeemableAmount = vested - redeemAmount;

        // Check the redeemable amount
        uint256 redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);
        assertEq(redeemableAmount, expectedRedeemableAmount, "redeemable mismatch");

        // Warp to another time
        elapsed = 60_000;
        vm.warp(_VESTING_START + elapsed);

        vested = (_AMOUNT + _AMOUNT).mulDivDown(elapsed, _VESTING_DURATION);
        expectedRedeemableAmount = vested - redeemAmount;

        // Check the redeemable amount
        redeemableAmount = _linearVesting.redeemable(_ALICE, _derivativeTokenId);
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
        vm.prank(_ALICE);
        _linearVesting.wrap(_derivativeTokenId, _AMOUNT);
    }

    function test_wrap_givenAmountIsZero_reverts()
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.wrap(_derivativeTokenId, 0);
    }

    function test_wrap_givenInsufficientBalance_reverts() public givenDerivativeIsDeployed {
        // Expect revert (underflow)
        vm.expectRevert();

        // Call
        vm.prank(_ALICE);
        _linearVesting.wrap(_derivativeTokenId, _AMOUNT);
    }

    function test_wrap_givenWrappedTokenNotDeployed(uint256 wrapAmount_)
        public
        givenDerivativeIsDeployed
        givenAliceHasDerivativeTokens(_AMOUNT)
    {
        uint256 wrapAmount = bound(wrapAmount_, 1, _AMOUNT);

        // Call
        vm.prank(_ALICE);
        _linearVesting.wrap(_derivativeTokenId, wrapAmount);

        // Get the token metadata
        Derivative.Token memory tokenMetadata = _linearVesting.getTokenMetadata(_derivativeTokenId);

        // Check values
        assertEq(
            _linearVesting.balanceOf(_ALICE, _derivativeTokenId),
            _AMOUNT - wrapAmount,
            "derivative: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(tokenMetadata.wrapped).balanceOf(_ALICE),
            wrapAmount,
            "wrapped derivative: balanceOf mismatch"
        );

        // Check total supply
        assertEq(
            _linearVesting.totalSupply(_derivativeTokenId),
            _AMOUNT - wrapAmount,
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
        givenAliceHasDerivativeTokens(_AMOUNT)
    {
        uint256 wrapAmount = bound(wrapAmount_, 1, _AMOUNT);

        // Call
        vm.prank(_ALICE);
        _linearVesting.wrap(_derivativeTokenId, wrapAmount);

        // Check values
        assertEq(
            _linearVesting.balanceOf(_ALICE, _derivativeTokenId),
            _AMOUNT - wrapAmount,
            "derivative: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE),
            wrapAmount,
            "wrapped derivative: balanceOf mismatch"
        );

        // Check total supply
        assertEq(
            _linearVesting.totalSupply(_derivativeTokenId),
            _AMOUNT - wrapAmount,
            "derivative: totalSupply mismatch"
        );
        assertEq(
            SoulboundCloneERC20(_derivativeWrappedAddress).totalSupply(),
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
        vm.prank(_ALICE);
        _linearVesting.unwrap(_derivativeTokenId, _AMOUNT);
    }

    function test_unwrap_givenAmountIsZero_reverts()
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(_AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.unwrap(_derivativeTokenId, 0);
    }

    function test_unwrap_givenWrappedTokenNotDeployed() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.InvalidParams.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.unwrap(_derivativeTokenId, _AMOUNT);
    }

    function test_unwrap_givenInsufficientBalance_reverts()
        public
        givenWrappedDerivativeIsDeployed
    {
        // Expect revert (underflow)
        vm.expectRevert();

        // Call
        vm.prank(_ALICE);
        _linearVesting.unwrap(_derivativeTokenId, _AMOUNT);
    }

    function test_unwrap(uint256 unwrapAmount_)
        public
        givenWrappedDerivativeIsDeployed
        givenAliceHasWrappedDerivativeTokens(_AMOUNT)
    {
        uint256 unwrapAmount = bound(unwrapAmount_, 1, _AMOUNT);

        // Call
        vm.prank(_ALICE);
        _linearVesting.unwrap(_derivativeTokenId, unwrapAmount);

        // Check values
        assertEq(
            _linearVesting.balanceOf(_ALICE, _derivativeTokenId),
            unwrapAmount,
            "derivative: balanceOf mismatch"
        );
        assertEq(
            SoulboundCloneERC20(_derivativeWrappedAddress).balanceOf(_ALICE),
            _AMOUNT - unwrapAmount,
            "wrapped derivative: balanceOf mismatch"
        );

        // Check total supply
        assertEq(
            _linearVesting.totalSupply(_derivativeTokenId),
            unwrapAmount,
            "derivative: totalSupply mismatch"
        );
        assertEq(
            SoulboundCloneERC20(_derivativeWrappedAddress).totalSupply(),
            _AMOUNT - unwrapAmount,
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
        _linearVesting.name(_derivativeTokenId);
    }

    function test_name() public givenDerivativeIsDeployed {
        // Call
        string memory name = _linearVesting.name(_derivativeTokenId);

        // Check values
        assertEq(name, _wrappedDerivativeTokenName);
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
        _linearVesting.symbol(_derivativeTokenId);
    }

    function test_symbol() public givenDerivativeIsDeployed {
        // Call
        string memory symbol = _linearVesting.symbol(_derivativeTokenId);

        // Check values
        assertEq(symbol, _wrappedDerivativeTokenSymbol);
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
        _linearVesting.decimals(_derivativeTokenId);
    }

    function test_decimals() public givenDerivativeIsDeployed {
        // Call
        uint8 decimals = _linearVesting.decimals(_derivativeTokenId);

        // Check values
        assertEq(decimals, _underlyingTokenDecimals);
    }

    // balanceOf
    // [X] when the token id is invalid
    //  [X] it returns 0
    // [X] it returns the balance of the unwrapped derivative token

    function test_balanceOf_givenTokenIdDoesNotExist() public {
        // Call
        uint256 balance = _linearVesting.balanceOf(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(balance, 0);
    }

    function test_balanceOf(uint256 amount_) public givenWrappedDerivativeIsDeployed {
        uint256 amount = bound(amount_, 0, _AMOUNT);

        // Mint
        if (amount > 0) {
            _mintDerivativeTokens(_ALICE, amount);
        }

        // Call
        uint256 balance = _linearVesting.balanceOf(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(balance, amount);
    }

    function test_balanceOf_wrapped(uint256 amount_) public givenWrappedDerivativeIsDeployed {
        uint256 amount = bound(amount_, 0, _AMOUNT);

        // Mint
        if (amount > 0) {
            _mintWrappedDerivativeTokens(_ALICE, amount);
        }

        // Call
        uint256 balance = _linearVesting.balanceOf(_ALICE, _derivativeTokenId);

        // Check values
        assertEq(balance, 0);
    }

    // totalSupply
    // [X] when the token id is invalid
    //  [X] it returns 0
    // [X] it returns the total supply of the unwrapped derivative token

    function test_totalSupply_givenTokenIdDoesNotExist() public {
        // Call
        uint256 balance = _linearVesting.totalSupply(_derivativeTokenId);

        // Check values
        assertEq(balance, 0);
    }

    function test_totalSupply(uint256 amount_) public givenWrappedDerivativeIsDeployed {
        uint256 amount = bound(amount_, 0, _AMOUNT);

        // Mint
        if (amount > 0) {
            _mintDerivativeTokens(_ALICE, amount);
        }

        // Call
        uint256 totalSupply = _linearVesting.totalSupply(_derivativeTokenId);

        // Check values
        assertEq(totalSupply, amount);
    }

    function test_totalSupply_wrapped(uint256 amount_) public givenWrappedDerivativeIsDeployed {
        uint256 amount = bound(amount_, 0, _AMOUNT);

        // Mint
        if (amount > 0) {
            _mintWrappedDerivativeTokens(_ALICE, amount);
        }

        // Call
        uint256 totalSupply = _linearVesting.totalSupply(_derivativeTokenId);

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
        _linearVesting.reclaim(_derivativeTokenId);
    }

    // transfer
    // [X] it reverts

    function test_transfer_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.NotPermitted.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.transfer(address(0x4), _derivativeTokenId, _AMOUNT);
    }

    // transferFrom
    // [X] it reverts

    function test_transferFrom_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.NotPermitted.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.transferFrom(_ALICE, address(0x4), _derivativeTokenId, _AMOUNT);
    }

    // approve
    // [X] it reverts

    function test_approve_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(LinearVesting.NotPermitted.selector);
        vm.expectRevert(err);

        // Call
        vm.prank(_ALICE);
        _linearVesting.approve(address(0x4), _derivativeTokenId, _AMOUNT);
    }

    // exerciseCost
    // [X] it reverts

    function test_exerciseCost_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.exerciseCost(bytes(""), _derivativeTokenId);
    }

    // convertsTo
    // [X] it reverts

    function test_convertsTo_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.convertsTo(bytes(""), _derivativeTokenId);
    }

    // transform
    // [X] it reverts

    function test_transform_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.transform(_derivativeTokenId, _ALICE, _AMOUNT);
    }

    // exercise
    // [X] it reverts

    function test_exercise_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(Derivative.Derivative_NotImplemented.selector);
        vm.expectRevert(err);

        // Call
        _linearVesting.exercise(_derivativeTokenId, _AMOUNT);
    }
}
