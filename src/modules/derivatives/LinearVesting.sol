// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC6909} from "solmate/tokens/ERC6909.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ClonesWithImmutableArgs} from "src/lib/clones/ClonesWithImmutableArgs.sol";
import {Timestamp} from "src/lib/Timestamp.sol";
import {ERC6909Metadata} from "src/lib/ERC6909Metadata.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Derivative, DerivativeModule} from "src/modules/Derivative.sol";
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";
import {SoulboundCloneERC20} from "src/modules/derivatives/SoulboundCloneERC20.sol";

/// @title      LinearVesting
/// @notice     A derivative module that allows for the creation of linearly vesting tokens
/// @dev        This module allows for the creation of linearly vesting tokens, where the vesting
///             period is defined by a start and expiry timestamp. The tokens can be wrapped and
///             unwrapped, and the underlying tokens can be redeemed once vested.
///
///             The start timestamp enables vesting tokens to have a cliff, after which vesting commences.
/// @author     Axis Finance
contract LinearVesting is DerivativeModule {
    using SafeTransferLib for ERC20;
    using ClonesWithImmutableArgs for address;
    using Timestamp for uint48;
    using FixedPointMathLib for uint256;

    // ========== EVENTS ========== //

    event DerivativeCreated(
        uint256 indexed tokenId, uint48 start, uint48 expiry, address baseToken
    );

    event WrappedDerivativeCreated(uint256 indexed tokenId, address wrappedToken);

    event Wrapped(
        uint256 indexed tokenId, address indexed owner, uint256 amount, address wrappedToken
    );

    event Unwrapped(
        uint256 indexed tokenId, address indexed owner, uint256 amount, address wrappedToken
    );

    event Redeemed(uint256 indexed tokenId, address indexed owner, uint256 amount);

    // ========== ERRORS ========== //

    error BrokenInvariant();
    error InsufficientBalance();
    error NotPermitted();
    error InvalidParams();
    error UnsupportedToken(address token_);

    // ========== DATA STRUCTURES ========== //

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting starts
    /// @param      expiry      The timestamp at which the vesting expires
    /// @param      baseToken   The address of the token to vest
    struct VestingData {
        uint48 start;
        uint48 expiry;
        ERC20 baseToken;
    }

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting starts
    /// @param      expiry      The timestamp at which the vesting expires
    struct VestingParams {
        uint48 start;
        uint48 expiry;
    }

    uint256 internal immutable _VESTING_PARAMS_LEN = 64;

    // ========== STATE VARIABLES ========== //

    /// @notice     Stores the clonable implementation of the wrapped derivative token
    address internal immutable _IMPLEMENTATION;

    /// @notice     Stores the amount that a user has claimed
    mapping(address owner_ => mapping(uint256 tokenId_ => uint256 claimed_)) public userClaimed;

    // ========== MODULE SETUP ========== //

    constructor(address parent_) Module(parent_) {
        // Deploy the clone implementation
        _IMPLEMENTATION = address(new SoulboundCloneERC20());
    }

    /// @inheritdoc Module
    function TYPE() public pure override returns (Type) {
        return Type.Derivative;
    }

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("LIV"), 1);
    }

    // ========== MODIFIERS ========== //

    modifier onlyValidTokenId(uint256 tokenId_) {
        if (tokenMetadata[tokenId_].exists == false) revert InvalidParams();
        _;
    }

    modifier onlyDeployedWrapped(uint256 tokenId_) {
        if (tokenMetadata[tokenId_].wrapped == address(0)) {
            revert InvalidParams();
        }
        _;
    }

    // ========== TRANSFER ========== //

    /// @inheritdoc ERC6909
    /// @dev        Vesting tokens are soulbound/not transferable
    function transfer(address, uint256, uint256) public virtual override returns (bool) {
        revert NotPermitted();
    }

    /// @inheritdoc ERC6909
    /// @dev        Vesting tokens are soulbound/not transferable
    function transferFrom(
        address,
        address,
        uint256,
        uint256
    ) public virtual override returns (bool) {
        revert NotPermitted();
    }

    /// @inheritdoc ERC6909
    /// @dev        Vesting tokens are soulbound/not transferable
    function approve(address, uint256, uint256) public virtual override returns (bool) {
        revert NotPermitted();
    }

    // ========== DERIVATIVE MANAGEMENT ========== //

    /// @inheritdoc Derivative
    /// @dev        This function performs the following:
    ///             - Validates the parameters
    ///             - Deploys the derivative token if it does not already exist
    ///
    ///             This function reverts if:
    ///             - The parameters are in an invalid format
    ///             - The parameters fail validation
    ///
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             The abi-encoded `VestingParams` for the derivative token
    /// @param      wrapped_            Whether or not to wrap the derivative token
    /// @return     tokenId_            The ID of the derivative token
    /// @return     wrappedAddress_     The address of the wrapped derivative token (if applicable)
    function deploy(
        address underlyingToken_,
        bytes memory params_,
        bool wrapped_
    ) external virtual override returns (uint256 tokenId_, address wrappedAddress_) {
        // Decode parameters
        VestingParams memory params = _decodeVestingParams(params_);

        // Validate parameters
        if (_validate(underlyingToken_, params) == false) {
            revert InvalidParams();
        }

        // If necessary, deploy and store the data
        (uint256 tokenId, address wrappedAddress) =
            _deployIfNeeded(underlyingToken_, params, wrapped_);

        return (tokenId, wrappedAddress);
    }

    /// @notice     Mints the derivative token to the recipient, assuming that the derivative token has already been deployed
    ///
    /// @param      to_         The address of the recipient of the derivative token
    /// @param      tokenId_    The ID of the derivative token
    /// @param      amount_     The amount of the derivative token to mint
    /// @param      token_      The metadata for the derivative token
    /// @param      wrapped_    Whether or not to wrap the derivative token
    function _mintDeployed(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        Token storage token_,
        bool wrapped_
    ) internal {
        // If the token exists, it is already deployed. However, ensure the wrapped status is consistent.
        if (wrapped_) {
            _deployWrapIfNeeded(tokenId_, token_);
        }

        // Transfer collateral token to this contract
        {
            VestingData memory data = abi.decode(token_.data, (VestingData));
            uint256 balanceBefore = data.baseToken.balanceOf(address(this));
            data.baseToken.safeTransferFrom(msg.sender, address(this), amount_);

            // Ensure the correct amount was transferred
            if (data.baseToken.balanceOf(address(this)) < balanceBefore + amount_) {
                revert UnsupportedToken(address(data.baseToken));
            }
        }

        // If wrapped, mint the wrapped derivative token
        if (wrapped_) {
            if (token_.wrapped == address(0)) revert InvalidParams();

            SoulboundCloneERC20 wrappedToken = SoulboundCloneERC20(token_.wrapped);
            wrappedToken.mint(to_, amount_);
        } else {
            // Otherwise mint the normal derivative token
            _mint(to_, tokenId_, amount_);
        }
    }

    /// @inheritdoc Derivative
    /// @dev        This function performs the following:
    ///             - Validates the parameters
    ///             - Deploys the derivative token if it does not already exist
    ///             - Mints the derivative token to the recipient
    ///
    ///             This function reverts if:
    ///             - The parameters are in an invalid format
    ///             - The parameters fail validation
    ///             - `amount_` is 0
    ///             - Vesting for the derivative token with `tokenId_` has completed
    ///
    /// @param      to_                 The address of the recipient of the derivative token
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             The abi-encoded `VestingParams` for the derivative token
    /// @param      amount_             The amount of the derivative token to mint
    /// @param      wrapped_            Whether or not to wrap the derivative token
    /// @return     tokenId_            The ID of the derivative token
    /// @return     wrappedAddress_     The address of the wrapped derivative token (if applicable)
    /// @return     amountCreated_      The amount of the derivative token that was minted
    function mint(
        address to_,
        address underlyingToken_,
        bytes memory params_,
        uint256 amount_,
        bool wrapped_
    )
        external
        virtual
        override
        returns (uint256 tokenId_, address wrappedAddress_, uint256 amountCreated_)
    {
        // Can't mint 0
        if (amount_ == 0) revert InvalidParams();

        // Decode parameters
        VestingParams memory params = _decodeVestingParams(params_);

        // Validate parameters
        if (_validate(underlyingToken_, params) == false) {
            revert InvalidParams();
        }

        // If necessary, deploy and store the data
        (tokenId_,) = _deployIfNeeded(underlyingToken_, params, wrapped_);

        // Mint the derivative token
        Token storage token = tokenMetadata[tokenId_];

        _mintDeployed(to_, tokenId_, amount_, token, wrapped_);

        return (tokenId_, token.wrapped, amount_);
    }

    /// @inheritdoc Derivative
    /// @dev        This function performs the following:
    ///             - Mints the derivative token to the recipient
    ///
    ///             This function reverts if:
    ///             - `tokenId_` does not exist
    ///             - The amount to mint is 0
    ///             - Vesting for the derivative token with `tokenId_` has completed
    ///
    /// @param      to_                 The address of the recipient of the derivative token
    /// @param      tokenId_            The ID of the derivative token
    /// @param      amount_             The amount of the derivative token to mint
    /// @param      wrapped_            Whether or not to wrap the derivative token
    /// @return     uint256             The ID of the derivative token
    /// @return     adress              The address of the wrapped derivative token (if applicable)
    /// @return     uint256             The amount of the derivative token that was minted
    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override onlyValidTokenId(tokenId_) returns (uint256, address, uint256) {
        // Can't mint 0
        if (amount_ == 0) revert InvalidParams();

        Token storage token = tokenMetadata[tokenId_];
        VestingData memory data = abi.decode(token.data, (VestingData));

        // Ensure the expiry is in the future
        if (data.expiry < block.timestamp) revert InvalidParams();

        _mintDeployed(to_, tokenId_, amount_, token, wrapped_);

        return (tokenId_, token.wrapped, amount_);
    }

    /// @notice     Redeems the derivative token for the underlying base token
    /// @dev        This function assumes that validation has already been performed
    ///
    /// @param      tokenId_    The ID of the derivative token
    /// @param      user_       The address of the owner of the derivative token
    /// @param      amount_     The amount of the derivative token to redeem
    function _redeem(uint256 tokenId_, address user_, uint256 amount_) internal {
        Token storage tokenData = tokenMetadata[tokenId_];

        // Get the balances of the tokens
        uint256 derivativeBalance = balanceOf[user_][tokenId_];
        uint256 wrappedBalance = tokenData.wrapped == address(0)
            ? 0
            : SoulboundCloneERC20(tokenData.wrapped).balanceOf(user_);

        uint256 derivativeToBurn = amount_ > derivativeBalance ? derivativeBalance : amount_;
        uint256 wrappedToBurn = amount_ - derivativeToBurn;
        if (wrappedToBurn > wrappedBalance) {
            revert InsufficientBalance();
        }

        // Update the user's claimed amount
        userClaimed[user_][tokenId_] += amount_;

        // Burn the unwrapped tokens
        if (derivativeToBurn > 0) {
            _burn(user_, tokenId_, derivativeToBurn);
        }
        // Burn the wrapped tokens - will be 0 if not wrapped
        if (wrappedToBurn > 0) {
            SoulboundCloneERC20(tokenData.wrapped).burn(user_, wrappedToBurn);
        }

        // Transfer the underlying token to the owner
        VestingData memory vestingData = abi.decode(tokenData.data, (VestingData));
        vestingData.baseToken.safeTransfer(user_, amount_);

        // Emit event
        emit Redeemed(tokenId_, user_, amount_);
    }

    /// @inheritdoc Derivative
    function redeemMax(uint256 tokenId_) external virtual override onlyValidTokenId(tokenId_) {
        // Determine the redeemable amount
        uint256 redeemableAmount = redeemable(msg.sender, tokenId_);

        // If the redeemable amount is 0, revert
        if (redeemableAmount == 0) revert InsufficientBalance();

        // Redeem the tokens
        _redeem(tokenId_, msg.sender, redeemableAmount);
    }

    /// @inheritdoc Derivative
    /// @dev        This function reverts if:
    ///             - `amount_` is 0
    ///             - The redeemable amount is less than `amount_`
    ///             - The derivative token with `tokenId_` has not been deployed
    function redeem(
        uint256 tokenId_,
        uint256 amount_
    ) external virtual override onlyValidTokenId(tokenId_) {
        if (amount_ == 0) revert InvalidParams();

        // Get the redeemable amount
        uint256 redeemableAmount = redeemable(msg.sender, tokenId_);

        // If the redeemable amount is less than the requested amount, revert
        if (redeemableAmount < amount_) revert InsufficientBalance();

        // Redeem the tokens
        _redeem(tokenId_, msg.sender, amount_);
    }

    /// @notice     Returns the amount of vested tokens that can be redeemed for the underlying base token
    /// @dev        The redeemable amount is computed as:
    ///             - The amount of tokens that have vested
    ///               - x: number of vestable tokens
    ///               - t: current timestamp
    ///               - s: start timestamp
    ///               - T: expiry timestamp
    ///               - Vested = x * (t - s) / (T - s)
    ///             - Minus the amount of tokens that have already been redeemed
    ///
    /// @param      owner_      The address of the owner of the derivative token
    /// @param      tokenId_    The ID of the derivative token
    /// @return     uint256     The amount of tokens that can be redeemed
    function redeemable(
        address owner_,
        uint256 tokenId_
    ) public view virtual override onlyValidTokenId(tokenId_) returns (uint256) {
        // Get the vesting data
        Token storage token = tokenMetadata[tokenId_];
        VestingData memory data = abi.decode(token.data, (VestingData));

        // If before the start time, 0
        if (block.timestamp <= data.start) return 0;

        // Get balances
        uint256 derivativeBalance = balanceOf[owner_][tokenId_];
        uint256 wrappedBalance =
            token.wrapped == address(0) ? 0 : SoulboundCloneERC20(token.wrapped).balanceOf(owner_);
        uint256 claimedBalance = userClaimed[owner_][tokenId_];
        uint256 totalAmount = derivativeBalance + wrappedBalance + claimedBalance;

        // Determine the amount that has been vested until date, excluding what has already been claimed
        uint256 vested;
        // If after the expiry time, all tokens are redeemable
        if (block.timestamp >= data.expiry) {
            vested = totalAmount;
        }
        // If before the expiry time, calculate what has vested already
        else {
            vested = totalAmount.mulDivDown(block.timestamp - data.start, data.expiry - data.start);
        }

        // Check invariant: cannot have claimed more than vested
        if (vested < claimedBalance) {
            revert BrokenInvariant();
        }

        // Deduct already claimed tokens
        vested -= claimedBalance;

        return vested;
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function exercise(uint256, uint256) external virtual override {
        revert Derivative.Derivative_NotImplemented();
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function reclaim(uint256) external virtual override {
        revert Derivative.Derivative_NotImplemented();
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function transform(uint256, address, uint256) external virtual override {
        revert Derivative.Derivative_NotImplemented();
    }

    /// @inheritdoc Derivative
    /// @dev        This function will revert if:
    ///             - The derivative token with `tokenId_` has not been deployed
    ///             - `amount_` is 0
    function wrap(
        uint256 tokenId_,
        uint256 amount_
    ) external virtual override onlyValidTokenId(tokenId_) {
        if (amount_ == 0) revert InvalidParams();

        if (balanceOf[msg.sender][tokenId_] < amount_) revert InsufficientBalance();

        // Burn the derivative token
        _burn(msg.sender, tokenId_, amount_);

        // Ensure the wrapped derivative is deployed
        Token storage token = tokenMetadata[tokenId_];
        _deployWrapIfNeeded(tokenId_, token);

        // Mint the wrapped derivative
        SoulboundCloneERC20(token.wrapped).mint(msg.sender, amount_);

        emit Wrapped(tokenId_, msg.sender, amount_, token.wrapped);
    }

    /// @inheritdoc Derivative
    /// @dev        This function will revert if:
    ///             - The derivative token with `tokenId_` has not been deployed
    ///             - A wrapped derivative for `tokenId_` has not been deployed
    ///             - `amount_` is 0
    function unwrap(
        uint256 tokenId_,
        uint256 amount_
    ) external virtual override onlyValidTokenId(tokenId_) onlyDeployedWrapped(tokenId_) {
        if (amount_ == 0) revert InvalidParams();

        Token storage token = tokenMetadata[tokenId_];
        SoulboundCloneERC20 wrappedToken = SoulboundCloneERC20(token.wrapped);

        if (wrappedToken.balanceOf(msg.sender) < amount_) revert InsufficientBalance();

        // Burn the wrapped derivative token
        wrappedToken.burn(msg.sender, amount_);

        // Mint the derivative token
        _mint(msg.sender, tokenId_, amount_);

        emit Unwrapped(tokenId_, msg.sender, amount_, token.wrapped);
    }

    /// @notice     Validates the parameters for a derivative token
    /// @dev        This function performs the following checks:
    ///             - The start and expiry times are not 0
    ///             - The start time is before the expiry time
    ///             - The expiry time is in the future
    ///             - The underlying token is not the zero address
    ///
    ///             The start time does not have to be before the current block timestamp,
    ///             as it is possible to deploy and mint derivative tokens after the start time.
    ///
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      data_               The parameters for the derivative token
    /// @return     bool                True if the parameters are valid, otherwise false
    function _validate(
        address underlyingToken_,
        VestingParams memory data_
    ) internal view returns (bool) {
        // Revert if any of the timestamps are 0
        if (data_.start == 0 || data_.expiry == 0) return false;

        // Revert if start and expiry are the same (as it would result in a divide by 0 error)
        if (data_.start == data_.expiry) return false;

        // Check that the start time is before the expiry time
        if (data_.start >= data_.expiry) return false;

        // Check that the expiry time is in the future
        if (data_.expiry < block.timestamp) return false;

        // Check that the underlying token is not 0
        if (underlyingToken_ == address(0)) return false;

        return true;
    }

    /// @inheritdoc Derivative
    ///
    /// @param      params_     The abi-encoded `VestingParams` for the derivative token
    function validate(
        address underlyingToken_,
        bytes memory params_
    ) public view virtual override returns (bool) {
        // Decode the parameters
        VestingParams memory data = _decodeVestingParams(params_);

        return _validate(underlyingToken_, data);
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function exerciseCost(bytes memory, uint256) external view virtual override returns (uint256) {
        revert Derivative.Derivative_NotImplemented();
    }

    /// @inheritdoc Derivative
    function convertsTo(bytes memory, uint256) external view virtual override returns (uint256) {
        revert Derivative_NotImplemented();
    }

    /// @notice     Decodes the ABI-encoded `VestingParams` for a derivative token
    /// @dev        This function will revert if the parameters are not the correct length
    function _decodeVestingParams(bytes memory params_)
        internal
        pure
        returns (VestingParams memory)
    {
        if (params_.length != _VESTING_PARAMS_LEN) revert InvalidParams();

        return abi.decode(params_, (VestingParams));
    }

    /// @notice     Computes the ID of a derivative token
    /// @dev        The ID is computed as the hash of the parameters and hashed again with the module identifier.
    ///
    /// @param      base_       The address of the underlying token
    /// @param      start_      The timestamp at which the vesting starts
    /// @param      expiry_     The timestamp at which the vesting expires
    /// @return     uint256     The ID of the derivative token
    function _computeId(
        ERC20 base_,
        uint48 start_,
        uint48 expiry_
    ) internal pure returns (uint256) {
        return uint256(
            keccak256(abi.encodePacked(VEECODE(), keccak256(abi.encode(base_, start_, expiry_))))
        );
    }

    /// @inheritdoc Derivative
    ///
    /// @param      params_     The abi-encoded `VestingParams` for the derivative token
    function computeId(
        address underlyingToken_,
        bytes memory params_
    ) external pure virtual override returns (uint256) {
        // Decode the parameters
        VestingParams memory data = _decodeVestingParams(params_);
        ERC20 underlyingToken = ERC20(underlyingToken_);

        // Compute the ID
        return _computeId(underlyingToken, data.start, data.expiry);
    }

    /// @notice     Computes the name and symbol of a derivative token
    ///
    /// @param      base_       The address of the underlying token
    /// @param      expiry_     The timestamp at which the vesting expires
    /// @return     string      The name of the derivative token
    /// @return     string      The symbol of the derivative token
    function _computeNameAndSymbol(
        ERC20 base_,
        uint48 expiry_
    ) internal view returns (string memory, string memory) {
        // Get the date components
        (string memory year, string memory month, string memory day) = expiry_.toPaddedString();

        return (
            string(abi.encodePacked(base_.name(), " ", year, "-", month, "-", day)),
            string(abi.encodePacked(base_.symbol(), " ", year, "-", month, "-", day))
        );
    }

    /// @notice     Deploys the derivative token if it does not already exist
    /// @dev        If the derivative token does not exist, it will be deployed using a token id
    ///             computed from the parameters.
    ///
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             The parameters for the derivative token
    /// @param      wrapped_            Whether or not to wrap the derivative token
    /// @return     tokenId_            The ID of the derivative token
    /// @return     wrappedAddress_     The address of the wrapped derivative token
    function _deployIfNeeded(
        address underlyingToken_,
        VestingParams memory params_,
        bool wrapped_
    ) internal returns (uint256 tokenId_, address wrappedAddress_) {
        // Compute the token ID
        ERC20 underlyingToken = ERC20(underlyingToken_);
        tokenId_ = _computeId(underlyingToken, params_.start, params_.expiry);

        // Record the token metadata, if needed
        Token storage token = tokenMetadata[tokenId_];
        if (token.exists == false) {
            // Store derivative data
            token.exists = true;
            token.underlyingToken = underlyingToken_;
            token.data = abi.encode(
                VestingData({
                    start: params_.start,
                    expiry: params_.expiry,
                    baseToken: underlyingToken
                })
            ); // Store this so that the tokenId can be used as a lookup

            tokenMetadata[tokenId_] = token;

            // Emit event
            emit DerivativeCreated(tokenId_, params_.start, params_.expiry, underlyingToken_);
        }

        // Create a wrapped derivative, if needed
        if (wrapped_) {
            _deployWrapIfNeeded(tokenId_, token);
        }

        return (tokenId_, token.wrapped);
    }

    /// @notice     Deploys the wrapped derivative token if it does not already exist
    /// @dev        If the wrapped derivative token does not exist, it will be deployed
    ///
    /// @param      tokenId_            The ID of the derivative token
    /// @param      token_              The metadata for the derivative token
    /// @return     wrappedAddress      The address of the wrapped derivative token
    function _deployWrapIfNeeded(
        uint256 tokenId_,
        Token storage token_
    ) internal returns (address wrappedAddress) {
        // Create a wrapped derivative, if needed
        if (token_.wrapped == address(0)) {
            // Cannot deploy if there isn't a clonable implementation
            if (_IMPLEMENTATION == address(0)) revert InvalidParams();

            // Get the parameters
            VestingData memory data = abi.decode(token_.data, (VestingData));

            // Deploy the wrapped implementation
            (string memory name_, string memory symbol_) =
                _computeNameAndSymbol(data.baseToken, data.expiry);
            bytes memory wrappedTokenData = abi.encodePacked(
                bytes32(bytes(name_)), // Name
                bytes32(bytes(symbol_)), // Smybol
                uint8(data.baseToken.decimals()), // Decimals
                uint64(data.expiry), // Expiry timestamp
                address(this), // Owner
                address(data.baseToken) // Underlying
            );
            token_.wrapped = _IMPLEMENTATION.clone3(wrappedTokenData, bytes32(tokenId_));

            // Emit event
            emit WrappedDerivativeCreated(tokenId_, token_.wrapped);
        }

        return token_.wrapped;
    }

    // ========== ERC6909 METADATA ========== //

    /// @inheritdoc ERC6909Metadata
    /// @dev        This function reverts if:
    ///             - The token ID does not exist
    function name(uint256 tokenId_)
        public
        view
        virtual
        override
        onlyValidTokenId(tokenId_)
        returns (string memory)
    {
        Token storage token = tokenMetadata[tokenId_];
        VestingData memory data = abi.decode(token.data, (VestingData));

        (string memory name_,) = _computeNameAndSymbol(data.baseToken, data.expiry);
        return name_;
    }

    /// @inheritdoc ERC6909Metadata
    /// @dev        This function reverts if:
    ///             - The token ID does not exist
    function symbol(uint256 tokenId_)
        public
        view
        virtual
        override
        onlyValidTokenId(tokenId_)
        returns (string memory)
    {
        Token storage token = tokenMetadata[tokenId_];
        VestingData memory data = abi.decode(token.data, (VestingData));

        (, string memory symbol_) = _computeNameAndSymbol(data.baseToken, data.expiry);
        return symbol_;
    }

    /// @inheritdoc ERC6909Metadata
    /// @dev        This function reverts if:
    ///             - The token ID does not exist
    function decimals(uint256 tokenId_)
        public
        view
        virtual
        override
        onlyValidTokenId(tokenId_)
        returns (uint8)
    {
        Token storage token = tokenMetadata[tokenId_];
        VestingData memory data = abi.decode(token.data, (VestingData));

        return data.baseToken.decimals();
    }
}
