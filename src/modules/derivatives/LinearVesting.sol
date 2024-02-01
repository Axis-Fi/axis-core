/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC6909} from "solmate/tokens/ERC6909.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ClonesWithImmutableArgs} from "src/lib/clones/ClonesWithImmutableArgs.sol";

import {Derivative, DerivativeModule} from "src/modules/Derivative.sol";
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";
import {SoulboundCloneERC20} from "src/modules/derivatives/SoulboundCloneERC20.sol";

contract LinearVesting is DerivativeModule {
    using SafeTransferLib for ERC20;
    using ClonesWithImmutableArgs for address;

    // ========== EVENTS ========== //

    event DerivativeCreated(
        uint256 indexed tokenId_, uint48 start_, uint48 expiry_, address baseToken_
    );

    event WrappedDerivativeCreated(uint256 indexed tokenId_, address wrappedToken_);

    event Wrapped(
        uint256 indexed tokenId_, address indexed owner_, uint256 amount_, address wrappedToken_
    );

    event Unwrapped(
        uint256 indexed tokenId_, address indexed owner_, uint256 amount_, address wrappedToken_
    );

    event Redeemed(uint256 indexed tokenId_, address indexed owner_, uint256 amount_);

    // ========== ERRORS ========== //

    error BrokenInvariant();
    error InsufficientBalance();
    error NotPermitted();
    error InvalidParams();

    // ========== DATA STRUCTURES ========== //

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting begins
    /// @param      expiry      The timestamp at which the vesting expires
    /// @param      end         The timestamp at which the vesting redemption ends
    /// @param      baseToken   The address of the token to vest
    struct VestingData {
        uint48 start;
        uint48 expiry;
        uint48 end;
        ERC20 baseToken;
    }

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting begins
    /// @param      expiry      The timestamp at which the vesting expires
    /// @param      end         The timestamp at which the vesting redemption ends
    struct VestingParams {
        uint48 start;
        uint48 expiry;
        uint48 end;
    }

    // ========== STATE VARIABLES ========== //

    address internal _clone;

    /// @notice     Stores the vesting data for a particular token id
    mapping(uint256 tokenId => VestingData) public vestingData;

    /// @notice     Stores the amount of tokens that have been claimed for a particular token id and owner
    mapping(address owner => mapping(uint256 tokenId => uint256 claimed)) internal claimed;

    // ========== MODULE SETUP ========== //

    constructor(address parent_, address clone_) Module(parent_) {
        if (clone_ == address(0)) revert InvalidParams();
        _clone = clone_;
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
        if (tokenMetadata[tokenId_].wrapped == address(0)) revert InvalidParams();
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
        VestingParams memory params = abi.decode(params_, (VestingParams));

        // Validate parameters
        if (_validate(params) == false) revert InvalidParams();
        if (underlyingToken_ == address(0)) revert InvalidParams();

        // If necessary, deploy and store the data
        (uint256 tokenId, address wrappedAddress) =
            _deployIfNeeded(underlyingToken_, params, wrapped_);

        return (tokenId, wrappedAddress);
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
    ///             - `to_` is the zero address
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
        // Can't mint to 0
        if (to_ == address(0)) revert InvalidParams();

        // Decode parameters
        VestingParams memory params = abi.decode(params_, (VestingParams));

        // Validate parameters
        if (_validate(params) == false) revert InvalidParams();
        if (underlyingToken_ == address(0)) revert InvalidParams();

        // If necessary, deploy and store the data
        (uint256 tokenId, address wrappedAddress) =
            _deployIfNeeded(underlyingToken_, params, wrapped_);

        // Transfer collateral token to this contract
        ERC20(underlyingToken_).safeTransferFrom(msg.sender, address(this), amount_);

        // If not wrapped, mint as normal
        if (wrapped_ == false) {
            _mint(to_, tokenId, amount_);
        }
        // Otherwise mint the wrapped derivative token
        else {
            if (wrappedAddress == address(0)) revert InvalidParams();

            SoulboundCloneERC20 wrappedToken = SoulboundCloneERC20(wrappedAddress);
            wrappedToken.mint(to_, amount_);
        }

        return (tokenId, wrappedAddress, amount_);
    }

    /// @inheritdoc Derivative
    /// @dev        This function performs the following:
    ///             - Mints the derivative token to the recipient
    ///
    ///             This function reverts if:
    ///             - `tokenId_` does not exist
    ///             - The amount to mint is 0
    ///             - `to_` is the zero address
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
        // Can't mint to 0
        if (to_ == address(0)) revert InvalidParams();

        Token storage token = tokenMetadata[tokenId_];

        // If the token exists, it is already deployed. However, ensure the wrapped status is consistent.
        if (wrapped_) {
            _deployWrapIfNeeded(tokenId_, token);
        }

        // Transfer collateral token to this contract
        VestingData memory data = abi.decode(token.data, (VestingData));
        data.baseToken.safeTransferFrom(msg.sender, address(this), amount_);

        // If not wrapped, mint as normal
        if (wrapped_ == false) {
            _mint(to_, tokenId_, amount_);
        }
        // Otherwise mint the wrapped derivative token
        else {
            if (token.wrapped == address(0)) revert InvalidParams();

            SoulboundCloneERC20 wrappedToken = SoulboundCloneERC20(token.wrapped);
            wrappedToken.mint(to_, amount_);
        }

        return (tokenId_, token.wrapped, amount_);
    }

    /// @notice     Redeems the derivative token for the underlying base token
    /// @dev        This function assumes that validation has already been performed
    ///
    /// @param      tokenId_    The ID of the derivative token
    /// @param      amount_     The amount of the derivative token to redeem
    /// @param      wrapped_    Whether or not to redeem wrapped derivative tokens
    function _redeem(uint256 tokenId_, uint256 amount_, bool wrapped_) internal {
        // Update claimed amount
        claimed[msg.sender][tokenId_] += amount_;

        // Burn the derivative token
        if (wrapped_ == false) {
            _burn(msg.sender, tokenId_, amount_);
        }
        // Burn the wrapped derivative token
        else {
            Token storage tokenData = tokenMetadata[tokenId_];
            if (tokenData.wrapped == address(0)) revert InvalidParams();

            SoulboundCloneERC20 wrappedToken = SoulboundCloneERC20(tokenData.wrapped);
            wrappedToken.burn(msg.sender, amount_);
        }

        // Transfer the underlying token to the owner
        vestingData[tokenId_].baseToken.safeTransfer(msg.sender, amount_);

        // Emit event
        emit Redeemed(tokenId_, msg.sender, amount_);
    }

    /// @inheritdoc Derivative
    function redeemMax(
        uint256 tokenId_,
        bool wrapped_
    ) external virtual override onlyValidTokenId(tokenId_) {
        // Determine the redeemable amount
        uint256 redeemableAmount = redeemable(msg.sender, tokenId_, wrapped_);

        // If the redeemable amount is 0, revert
        if (redeemableAmount == 0) revert InsufficientBalance();

        // Redeem the tokens
        _redeem(tokenId_, redeemableAmount, wrapped_);
    }

    /// @inheritdoc Derivative
    function redeem(
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override onlyValidTokenId(tokenId_) {
        // Get the redeemable amount
        uint256 redeemableAmount = redeemable(msg.sender, tokenId_, wrapped_);

        // If the redeemable amount is 0, revert
        if (redeemableAmount == 0) revert InsufficientBalance();

        // If the redeemable amount is less than the requested amount, revert
        if (redeemableAmount < amount_) revert InsufficientBalance();

        // Redeem the tokens
        _redeem(tokenId_, amount_, wrapped_);
    }

    /// @notice     Returns the amount of vested tokens that can be redeemed for the underlying base token
    /// @dev        The redeemable amount is computed as:
    ///             - The amount of tokens that have vested
    ///               - x: number of vestable tokens
    ///               - t: current timestamp
    ///               - s: start timestamp
    ///               - T: end timestamp
    ///               - Vested = x * (t - s) / (T - s)
    ///             - Minus the amount of tokens that have already been redeemed
    ///
    /// @param      owner_      The address of the owner of the derivative token
    /// @param      tokenId_    The ID of the derivative token
    /// @return     uint256     The amount of tokens that can be redeemed
    function redeemable(
        address owner_,
        uint256 tokenId_,
        bool wrapped_
    ) public view virtual override onlyValidTokenId(tokenId_) returns (uint256) {
        // Get the vesting data
        VestingData storage data = vestingData[tokenId_];

        // If before the start time, 0
        if (block.timestamp < data.start) return 0;

        // Total = wrapped + derivative + claimed
        Token storage token = tokenMetadata[tokenId_];
        uint256 wrappedBalance =
            token.wrapped == address(0) ? 0 : SoulboundCloneERC20(token.wrapped).balanceOf(owner_);
        uint256 derivativeBalance = balanceOf[owner_][tokenId_];
        uint256 claimedBalance = claimed[owner_][tokenId_];
        uint256 totalAmount = derivativeBalance + wrappedBalance + claimedBalance;

        // Determine the amount that has been vested
        uint256 vested;
        // If after the end time, all tokens are redeemable
        if (block.timestamp >= data.expiry) {
            vested = totalAmount;
        }
        // If before the end time, calculate what has vested already
        else {
            vested = (totalAmount * (block.timestamp - data.start)) / (data.expiry - data.start);
        }

        // Check invariant: cannot have claimed more than vested
        if (vested < claimedBalance) {
            revert BrokenInvariant();
        }

        // TODO what happens after the end timestamp?

        // Deduct already claimed tokens
        vested -= claimedBalance;

        // The redeemable amount is dependent on whether or not the wrapped derivative is being redeemed
        // The vested amount could be split across wrapped and unwrapped tokens
        // Therefore, return the minimum of the two
        if (wrapped_) {
            return wrappedBalance < vested ? wrappedBalance : vested;
        } else {
            return derivativeBalance < vested ? derivativeBalance : vested;
        }
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function exercise(uint256, uint256, bool) external virtual override {
        revert Derivative.Derivative_NotImplemented();
    }

    /// @inheritdoc Derivative
    function reclaim(uint256 tokenId_)
        external
        virtual
        override
        onlyInternal
        onlyValidTokenId(tokenId_)
    {
        VestingData storage data = vestingData[tokenId_];
        // Can only be reclaimed after the end date
        if (block.timestamp < data.end) revert InvalidParams();

        // Transfer underlying tokens to the parent
        data.baseToken.safeTransfer(PARENT, data.baseToken.balanceOf(address(this)));

        // TODO burn?
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function transform(uint256, address, uint256, bool) external virtual override {
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

        // Burn the wrapped derivative token
        Token storage token = tokenMetadata[tokenId_];
        SoulboundCloneERC20(token.wrapped).burn(msg.sender, amount_);

        // Mint the derivative token
        _mint(msg.sender, tokenId_, amount_);

        emit Unwrapped(tokenId_, msg.sender, amount_, token.wrapped);
    }

    /// @notice     Validates the parameters for a derivative token
    /// @dev        This function performs the following checks:
    ///             - The start and expiry times are not 0
    ///             - The start time is before the expiry time
    ///             - The expiry time is in the future
    ///             - The base token is not the zero address
    ///
    /// @param      data_   The parameters for the derivative token
    /// @return     bool    True if the parameters are valid, otherwise false
    function _validate(VestingParams memory data_) internal view returns (bool) {
        // Revert if any of the timestamps are 0
        if (data_.start == 0 || data_.expiry == 0 || data_.end == 0) return false;

        // Revert if start and expiry are the same (as it would result in a divide by 0 error)
        if (data_.start == data_.expiry) return false;

        // Check that the start time is before the expiry time
        if (data_.start >= data_.expiry) return false;

        // Check that the expiry time is before the end time
        if (data_.expiry >= data_.end) return false;

        // Check that the start time is in the future
        if (data_.start < block.timestamp) return false;

        // Check that the expiry time is in the future
        if (data_.expiry < block.timestamp) return false;

        // Check that the end time is in the future
        if (data_.end < block.timestamp) return false;

        return true;
    }

    /// @inheritdoc Derivative
    ///
    /// @param      params_     The abi-encoded `VestingParams` for the derivative token
    function validate(bytes memory params_) public view virtual override returns (bool) {
        // Decode the parameters
        VestingParams memory data = abi.decode(params_, (VestingParams));

        return _validate(data);
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

    /// @notice     Computes the ID of a derivative token
    /// @dev        The ID is computed as the hash of the parameters and hashed again with the module identifier.
    ///
    /// @param      base_       The address of the underlying token
    /// @param      start_      The timestamp at which the vesting begins
    /// @param      expiry_     The timestamp at which the vesting ends
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
    function computeId(bytes memory params_) external pure virtual override returns (uint256) {
        // Decode the parameters
        VestingData memory data = abi.decode(params_, (VestingData));

        // Compute the ID
        return _computeId(data.baseToken, data.start, data.expiry);
    }

    /// @notice     Computes the name and symbol of a derivative token
    ///
    /// @param      base_       The address of the underlying token
    /// @param      start_      The timestamp at which the vesting begins
    /// @param      expiry_     The timestamp at which the vesting ends
    /// @return     string      The name of the derivative token
    /// @return     string      The symbol of the derivative token
    function _computeNameAndSymbol(
        ERC20 base_,
        uint48 start_,
        uint48 expiry_
    ) internal view returns (string memory, string memory) {
        return (
            string(abi.encodePacked(base_.name(), "-", start_, "-", expiry_)),
            string(abi.encodePacked(base_.symbol(), "-", start_, "-", expiry_))
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
            token.data = abi.encode(
                VestingData({
                    start: params_.start,
                    expiry: params_.expiry,
                    end: params_.end,
                    baseToken: underlyingToken
                })
            ); // Store this so that the tokenId can be used as a lookup
                // TODO are the other metadata fields needed?

            tokenMetadata[tokenId_] = token;

            // Add as a lot derivative
            // TODO needs lotId

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
            if (address(_clone) == address(0)) revert InvalidParams();

            // Get the parameters
            VestingData memory data = abi.decode(token_.data, (VestingData));

            // Deploy the wrapped implementation
            (string memory name, string memory symbol) =
                _computeNameAndSymbol(data.baseToken, data.start, data.expiry);
            bytes memory wrappedTokenData = abi.encodePacked(
                bytes32(bytes(name)), bytes32(bytes(symbol)), uint8(data.baseToken.decimals())
            );
            token_.wrapped = address(_clone).clone3(wrappedTokenData, bytes32(tokenId_));

            // Emit event
            emit WrappedDerivativeCreated(tokenId_, token_.wrapped);
        }

        return token_.wrapped;
    }
}
